import 'dart:async';
import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flashshare/api/storage_client.dart';
import 'package:flashshare/files/app_file.dart';
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
  final _progress = StreamController<UploadProgress>.broadcast();
  final _cancellers = <String, CancelToken>{};
  int _seq = 0;
  int _active = 0;
  void Function()? onIdle;

  UploadEngine(this._client, this._store, this._r2);

  StorageClient get client => _client;
  Stream<UploadProgress> get progress => _progress.stream;

  void _emit(UploadProgress p) => _progress.add(p);

  Future<void> enqueue(List<AppFile> files, UploadMode mode) async {
    if (files.isEmpty) return;
    if (mode == UploadMode.zip) {
      AppFile zip;
      try {
        zip = await _buildZip(files);
      } catch (e) {
        _emitError('flashshare.zip', 'flashshare.zip', 'Failed to build zip: $e');
        return;
      }
      _active++;
      await _uploadOne(zip);
      return;
    }
    if (mode == UploadMode.collection) {
      Collection col;
      try {
        col = await _client.createCollection(expectedFileCount: files.length);
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
      } catch (e) {
        _emitError(
            'collection', 'Collection', 'Failed to create collection: $e');
        return;
      }
      for (final f in files) {
        _active++;
        await _uploadOne(f, collectionId: col.id);
      }
      return;
    }
    for (final f in files) {
      _active++;
      await _uploadOne(f);
    }
  }

  Future<AppFile> _buildZip(List<AppFile> files) async {
    final arc = Archive();
    for (final f in files) {
      final bytes = await f.readAsBytes();
      arc.addFile(ArchiveFile(f.name, bytes.length, bytes));
    }
    final zipped = ZipEncoder().encode(arc);
    final ts = DateTime.now().millisecondsSinceEpoch;
    return BytesFile('flashshare-$ts.zip', Uint8List.fromList(zipped));
  }

  Future<void> _uploadOne(AppFile file, {String? collectionId}) async {
    final key = '${_seq++}:${file.name}';
    final name = file.name;
    final ct = guessContentType(name);
    final size = await file.getSize();
    final token = CancelToken();
    _cancellers[key] = token;
    try {
      _emit(UploadProgress(
          key: key,
          filename: name,
          state: UploadState.queued,
          bytesSent: 0,
          total: size));
      final init = await _client.uploadInit(name, ct, size);
      if (init.type == 'single') {
        await _putSingle(init.uploadUrl!, file, ct, size, key, token);
      } else {
        await _putMultipart(init, file, ct, size, key, token);
      }
      _emit(UploadProgress(
          key: key,
          filename: name,
          state: UploadState.confirming,
          bytesSent: size,
          total: size));
      final rec = await _client.uploadConfirm(
        filename: name,
        size: size,
        contentType: ct,
        r2Key: init.r2Key,
        collectionId: collectionId,
      );
      await _store.add(HistoryEntry(
        kind: 'file',
        id: rec.id,
        url: rec.url,
        filename: name,
        size: size,
        expiresAt: rec.expiresAt,
        ownerToken: rec.ownerToken,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ));
      _emit(UploadProgress(
          key: key,
          filename: name,
          state: UploadState.done,
          bytesSent: size,
          total: size,
          url: rec.url));
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        _emit(UploadProgress(
            key: key,
            filename: name,
            state: UploadState.cancelled,
            bytesSent: 0,
            total: size));
      } else {
        _emit(UploadProgress(
            key: key,
            filename: name,
            state: UploadState.error,
            bytesSent: 0,
            total: size,
            error: e.message));
      }
    } catch (e) {
      _emit(UploadProgress(
          key: key,
          filename: name,
          state: UploadState.error,
          bytesSent: 0,
          total: size,
          error: e.toString()));
    } finally {
      _cancellers.remove(key);
      _active--;
      if (_active == 0) onIdle?.call();
    }
  }

  Options _putOptions(String ct) => Options(
        method: 'PUT',
        headers: {'Content-Type': ct},
        contentType: ct,
      );

  Future<void> _putSingle(String url, AppFile file, String ct, int size,
      String key, CancelToken token) async {
    // Stream the body on native (avoids buffering the whole file, which used to
    // OOM-kill the app on large mobile uploads). Dio's browser adapter can't
    // stream a request body, so on web send the in-memory bytes as before.
    final body = kIsWeb ? await file.readAsBytes() : file.openRead();
    await _r2.put(url,
        data: body,
        cancelToken: token,
        options: Options(
          method: 'PUT',
          headers: {
            'Content-Type': ct,
            'Content-Length': size.toString(),
          },
        ),
        onSendProgress: (s, t) => _emit(UploadProgress(
            key: key,
            filename: file.name,
            state: UploadState.uploading,
            bytesSent: s,
            total: size)));
  }

  void _emitError(String key, String name, String? error) => _emit(UploadProgress(
      key: key,
      filename: name,
      state: UploadState.error,
      bytesSent: 0,
      total: 0,
      error: error));

  Future<void> _putMultipart(UploadInit init, AppFile file, String ct, int size,
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
      // Send bounded bytes per chunk; partSize caps the memory per chunk.
      final chunk = await file.readRange(start, end);
      final resp = await _r2.put(url!,
          data: chunk,
          cancelToken: token,
          options: _putOptions(ct),
          onSendProgress: (s, t) => _emit(UploadProgress(
              key: key,
              filename: file.name,
              state: UploadState.uploading,
              bytesSent: start + s,
              total: size)));
      parts.add(PartEtag(p, resp.headers.value('etag') ?? ''));
    }
    await _client.uploadCompleteMultipart(init.uploadId!, parts, init.ownerToken!);
  }

  void cancel(String key) => _cancellers[key]?.cancel('user');
}
