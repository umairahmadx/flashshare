import 'dart:async';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flashshare/api/storage_client.dart';
import 'package:flashshare/models.dart';
import 'package:flashshare/storage/history_store.dart';

enum UploadMode { separate, zip, collection }

enum UploadState { queued, uploading, confirming, done, error, cancelled }

class UploadProgress {
  final String key;
  final String filename;
  final UploadState state;
  final int bytesSent;
  final int total;
  final String? url;
  final String? error;
  UploadProgress({
    required this.key,
    required this.filename,
    required this.state,
    required this.bytesSent,
    required this.total,
    this.url,
    this.error,
  });
}

class UploadEngine {
  final StorageClient _client;
  final HistoryStore _store;
  final Dio _r2;
  final Future<Directory> Function()? tempDirProvider;
  final _progress = StreamController<UploadProgress>.broadcast();
  final _cancellers = <String, CancelToken>{};

  UploadEngine(this._client, this._store, this._r2,
      [this.tempDirProvider]);

  StorageClient get client => _client;
  Stream<UploadProgress> get progress => _progress.stream;

  void _emit(UploadProgress p) => _progress.add(p);

  Future<void> enqueue(List<File> files, UploadMode mode) async {
    if (files.isEmpty) return;
    if (mode == UploadMode.zip) {
      final zip = await _buildZip(files);
      await _uploadOne(zip, zip.path.split(Platform.pathSeparator).last);
    } else if (mode == UploadMode.collection) {
      final col =
          await _client.createCollection(expectedFileCount: files.length);
      await _store.add(HistoryEntry(
        kind: 'collection',
        id: col.id,
        url: col.url,
        filename: 'Collection (${files.length} files)',
        size: 0,
        expiresAt: col.expiresAt,
        ownerToken: col.ownerToken,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ));
      for (final f in files) {
        await _uploadOne(
            f, f.path.split(Platform.pathSeparator).last, collectionId: col.id);
      }
    } else {
      for (final f in files) {
        await _uploadOne(f, f.path.split(Platform.pathSeparator).last);
      }
    }
  }

  Future<File> _buildZip(List<File> files) async {
    final arc = Archive();
    for (final f in files) {
      final bytes = await f.readAsBytes();
      arc.addFile(ArchiveFile(
          f.path.split(Platform.pathSeparator).last, bytes.length, bytes));
    }
    final zipped = ZipEncoder().encode(arc)!;
    final dir = await (tempDirProvider ?? getTemporaryDirectory)();
    final out =
        File('${dir.path}/flashshare-${DateTime.now().millisecondsSinceEpoch}.zip');
    await out.writeAsBytes(zipped);
    return out;
  }

  Future<void> _uploadOne(File file, String filename,
      {String? collectionId}) async {
    final key = file.path;
    final ct = guessContentType(filename);
    final size = await file.length();
    final token = CancelToken();
    _cancellers[key] = token;
    _emit(UploadProgress(
        key: key,
        filename: filename,
        state: UploadState.queued,
        bytesSent: 0,
        total: size));
    try {
      final init = await _client.uploadInit(filename, ct, size);
      if (init.type == 'single') {
        await _putSingle(init.uploadUrl!, file, ct, size, key, token);
      } else {
        await _putMultipart(init, file, ct, size, key, token);
      }
      _emit(UploadProgress(
          key: key,
          filename: filename,
          state: UploadState.confirming,
          bytesSent: size,
          total: size));
      final rec = await _client.uploadConfirm(
        filename: filename,
        size: size,
        contentType: ct,
        r2Key: init.r2Key,
        collectionId: collectionId,
      );
      await _store.add(HistoryEntry(
        kind: 'file',
        id: rec.id,
        url: rec.url,
        filename: filename,
        size: size,
        expiresAt: rec.expiresAt,
        ownerToken: rec.ownerToken,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ));
      _emit(UploadProgress(
          key: key,
          filename: filename,
          state: UploadState.done,
          bytesSent: size,
          total: size,
          url: rec.url));
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        _emit(UploadProgress(
            key: key,
            filename: filename,
            state: UploadState.cancelled,
            bytesSent: 0,
            total: size));
      } else {
        _emit(UploadProgress(
            key: key,
            filename: filename,
            state: UploadState.error,
            bytesSent: 0,
            total: size,
            error: e.message));
      }
    } catch (e) {
      _emit(UploadProgress(
          key: key,
          filename: filename,
          state: UploadState.error,
          bytesSent: 0,
          total: size,
          error: e.toString()));
    } finally {
      _cancellers.remove(key);
    }
  }

  Options _putOptions(String ct) => Options(
        method: 'PUT',
        headers: {'Content-Type': ct},
        contentType: ct,
      );

  Future<void> _putSingle(String url, File file, String ct, int size,
      String key, CancelToken token) async {
    await _r2.put(url,
        data: file.openRead(),
        cancelToken: token,
        options: _putOptions(ct),
        onSendProgress: (s, t) => _emit(UploadProgress(
            key: key,
            filename: key.split(Platform.pathSeparator).last,
            state: UploadState.uploading,
            bytesSent: s,
            total: size)));
  }

  Future<void> _putMultipart(UploadInit init, File file, String ct, int size,
      String key, CancelToken token) async {
    final partSize = init.partSize!;
    final totalParts = init.totalParts!;
    final urls = Map<String, String>.from(init.initialUrls ?? {});
    final parts = <PartEtag>[];
    for (var p = 1; p <= totalParts; p++) {
      var url = urls[p.toString()];
      if (url == null) {
        final got = await _client.uploadParts(init.uploadId!, [p], init.ownerToken!);
        url = got[p];
      }
      final start = (p - 1) * partSize;
      final end = (start + partSize < size) ? start + partSize : size;
      final chunk = file.openRead(start, end);
      final resp = await _r2.put(url!,
          data: chunk,
          cancelToken: token,
          options: _putOptions(ct),
          onSendProgress: (s, t) => _emit(UploadProgress(
              key: key,
              filename: key.split(Platform.pathSeparator).last,
              state: UploadState.uploading,
              bytesSent: start + s,
              total: size)));
      parts.add(PartEtag(p, resp.headers.value('etag') ?? ''));
    }
    await _client.uploadCompleteMultipart(init.uploadId!, parts, init.ownerToken!);
  }

  void cancel(String key) => _cancellers[key]?.cancel('user');
}
