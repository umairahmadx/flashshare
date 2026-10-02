import 'dart:async';
import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:pdfx/pdfx.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:flashshare/api/storage_client.dart';
import 'package:flashshare/files/app_file.dart';
import 'package:flashshare/logs/log_store.dart';
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

  Future<void> enqueue(List<AppFile> files, UploadMode mode,
      {ShareOptions? options}) async {
    if (files.isEmpty) return;
    // One active-batch counter for the whole enqueue, so the idle callback
    // (which stops the foreground service) fires once when the whole batch
    // drains — not after every single file.
    _active++;
    try {
      if (mode == UploadMode.zip) {
        AppFile zip;
        try {
          zip = await _buildZip(files);
        } catch (e) {
          _emitError('flashshare.zip', 'flashshare.zip', 'Failed to build zip: $e');
          return;
        }
        await _uploadOne(zip, options: options);
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
            locked: options?.password != null,
          ));
        } catch (e) {
          _emitError(
              'collection', 'Collection', 'Failed to create collection: $e');
          return;
        }
        // Collection-level settings (password/expiry/max-downloads) apply to
        // the whole share link, so set them once on the collection.
        await _applyOptions('collection', col.id, col.ownerToken, options);
        for (final f in files) {
          await _uploadOne(f, collectionId: col.id);
        }
        return;
      }
      for (final f in files) {
        await _uploadOne(f, options: options);
      }
    } finally {
      _active--;
      if (_active == 0) onIdle?.call();
    }
  }

  /// Push ShareOptions to the owner-only settings endpoints. Best-effort per
  /// field: a failure on one setting (e.g. premium-only permanent expiry)
  /// shouldn't take down the upload it decorates.
  Future<void> _applyOptions(
      String kind, String id, String ownerToken, ShareOptions? o) async {
    if (o == null || o.isEmpty) return;
    if (o.password != null) {
      try {
        await _client.setPassword(kind, id, o.password!, ownerToken);
      } catch (e) {
        LogStore.instanceOrNull?.warning('Password setting failed: $e');
      }
    }
    if (o.expiryDays != null) {
      try {
        await _client.setExpiry(kind, id, o.expiryDays, ownerToken);
      } catch (e) {
        LogStore.instanceOrNull?.warning('Expiry setting failed: $e');
      }
    }
    if (o.maxDownloads != null) {
      try {
        await _client.setMaxDownloads(kind, id, o.maxDownloads, ownerToken);
      } catch (e) {
        LogStore.instanceOrNull?.warning('Max-downloads setting failed: $e');
      }
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

  Future<void> _uploadOne(AppFile file,
      {String? collectionId, ShareOptions? options}) async {
    final key = '${_seq++}:${file.name}';
    final name = file.name;
    UploadInit? init;
    int size = 0;
    final token = CancelToken();
    _cancellers[key] = token;
    try {
      size = await file.getSize();
      LogStore.instanceOrNull?.info('Uploading "$name" (${formatBytes(size)})');
      _emit(UploadProgress(
          key: key,
          filename: name,
          state: UploadState.queued,
          bytesSent: 0,
          total: size));
      final ct = guessContentType(name);
      init = await _client.uploadInit(name, ct, size);
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
        locked: options?.password != null,
      ));

      // Files inside a collection inherit the collection's settings; only
      // apply per-file options to standalone uploads.
      if (collectionId == null) {
        await _applyOptions('file', rec.id, rec.ownerToken, options);
      }

      // Background task: generate and cache a thumbnail locally so it shows
      // up instantly in the History list without a network download.
      unawaited(_cacheThumbnail(file, rec.url, id: rec.id, token: rec.ownerToken));

      _emit(UploadProgress(
          key: key,
          filename: name,
          state: UploadState.done,
          bytesSent: size,
          total: size,
          url: rec.url));
      LogStore.instanceOrNull?.info('Uploaded "$name" -> ${rec.url}');
    } on DioException catch (e) {
      final cancelled = e.type == DioExceptionType.cancel;
      // A half-finished multipart upload holds server-side state (and
      // quota); it must be aborted on cancel and on any failure.
      if (init != null && init.type == 'multipart') {
        try {
          await _client.uploadAbort(init.uploadId!, init.ownerToken!);
        } catch (_) {
          // Best-effort cleanup; the server expires stale uploads anyway.
        }
      }
      if (cancelled) {
        LogStore.instanceOrNull?.warning('Upload of "$name" cancelled');
        _emit(UploadProgress(
            key: key,
            filename: name,
            state: UploadState.cancelled,
            bytesSent: 0,
            total: size));
      } else {
        final msg = e.message ?? 'Network error (${e.type.name})';
        LogStore.instanceOrNull
            ?.error('Upload of "$name" failed: $msg', stack: e.stackTrace);
        _emit(UploadProgress(
            key: key,
            filename: name,
            state: UploadState.error,
            bytesSent: 0,
            total: size,
            error: msg));
      }
    } catch (e, st) {
      // Non-Dio failures mid-multipart (e.g. a bad part URL) must also abort.
      if (init != null && init.type == 'multipart') {
        try {
          await _client.uploadAbort(init.uploadId!, init.ownerToken!);
        } catch (_) {}
      }
      LogStore.instanceOrNull
          ?.error('Upload of "$name" failed: $e', stack: st);
      _emit(UploadProgress(
          key: key,
          filename: name,
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

  void _emitError(String key, String name, String? error) {
    LogStore.instanceOrNull?.error(error ?? 'Unknown error');
    _emit(UploadProgress(
      key: key,
      filename: name,
      state: UploadState.error,
      bytesSent: 0,
      total: 0,
      error: error,
    ));
  }

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
        if (url == null) {
          throw StateError('No presigned URL for part $p');
        }
      }
      final start = (p - 1) * partSize;
      final end = (start + partSize < size) ? start + partSize : size;
      // Send bounded bytes per chunk; partSize caps the memory per chunk.
      final chunk = await file.readRange(start, end);
      final resp = await _r2.put(url,
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

  /// Re-apply share options to an existing history entry (owner-only).
  /// A null password on a previously locked share removes the password.
  /// Returns the updated entry on success.
  Future<HistoryEntry> applyOptions(
      HistoryEntry e, ShareOptions options) async {
    if (options.password != null) {
      await _client.setPassword(e.kind, e.id, options.password!, e.ownerToken);
    } else if (e.locked) {
      await _client.removePassword(e.kind, e.id, e.ownerToken);
    }
    if (options.expiryDays != null) {
      await _client.setExpiry(e.kind, e.id, options.expiryDays, e.ownerToken);
    }
    if (options.maxDownloads != null) {
      await _client.setMaxDownloads(
          e.kind, e.id, options.maxDownloads, e.ownerToken);
    }
    final updated = e.copyWith(locked: options.password != null);
    await _store.update(updated);
    return updated;
  }

  Future<void> _cacheThumbnail(AppFile file, String url,
      {String? id, String? token}) async {
    if (kIsWeb) return; // CacheManager/File ops generally native-only here.
    // Which step we were on when something threw. pdfx reports every native
    // failure as a bare "Unknown error" (with an obfuscated stack), so the
    // log needs our own breadcrumb to be actionable.
    var stage = 'read bytes';
    try {
      final ext = file.name.split('.').last.toLowerCase();
      Uint8List? thumb;

      if (['jpg', 'jpeg', 'png', 'webp', 'gif'].contains(ext)) {
        // For images, we can just cache the original file bytes as the thumbnail.
        thumb = await file.readAsBytes();
      } else if (['mp4', 'mov', 'avi', 'mkv'].contains(ext) && file.path != null) {
        // For videos, generate a frame.
        stage = 'video frame';
        thumb = await VideoThumbnail.thumbnailData(
          video: file.path!,
          imageFormat: ImageFormat.JPEG,
          maxWidth: 256,
          quality: 75,
        );
      } else if (ext == 'pdf') {
        // For PDFs, render the first page.
        stage = 'pdf open';
        PdfDocument doc;
        try {
          doc = file.path != null
              ? await PdfDocument.openFile(file.path!)
              : await PdfDocument.openData(await file.readAsBytes());
        } on PlatformException {
          // The path isn't readable (stale picker/share cache, scoped
          // storage) even though it pointed at a real file earlier — the
          // bytes still are, so render from memory instead of giving up.
          doc = await PdfDocument.openData(await file.readAsBytes());
        }
        try {
          stage = 'pdf page';
          final page = await doc.getPage(1);
          stage = 'pdf render';
          final pageImg = await page.render(
            width: page.width / 2,
            height: page.height / 2,
            format: PdfPageImageFormat.jpeg,
            quality: 75,
          );
          thumb = pageImg?.bytes;
          stage = 'pdf close';
        } finally {
          await doc.close();
        }
      }

      if (thumb != null) {
        stage = 'cache write';
        await DefaultCacheManager().putFile(url, thumb, fileExtension: 'jpg');
        // Also push the thumbnail to the server so it shows on the public
        // download page (video/image files). Local-only for PDFs (the API
        // docs scope thumbnails to "video or image file" - don't fight it).
        if (id != null && token != null && !['pdf'].contains(ext)) {
          try {
            if (thumb.length <= 2 * 1024 * 1024) {
              await _client.uploadThumbnail(id, thumb, token);
            }
          } catch (err) {
            LogStore.instanceOrNull?.warning('Thumbnail upload failed: $err');
          }
        }
      }
    } on PlatformException catch (e) {
      LogStore.instanceOrNull?.warning('Thumbnail caching failed for '
          '"${file.name}" at $stage: ${_describePlatformError(e)}');
    } catch (e) {
      LogStore.instanceOrNull?.warning(
          'Thumbnail caching failed for "${file.name}" at $stage: $e');
    }
  }

  /// One-line rendering of a [PlatformException].
  ///
  /// pdfx (Pigeon) stuffs a multi-line native stack into `details`, which
  /// would bury the in-app log screen in noise; keep code + message + cause.
  static String _describePlatformError(PlatformException e) {
    final details = e.details?.toString() ?? '';
    const causePrefix = 'Cause: ';
    const stackMarker = ', Stacktrace:';
    final cause = details.startsWith(causePrefix) &&
            details.contains(stackMarker)
        ? details
            .substring(causePrefix.length, details.indexOf(stackMarker))
            .trim()
        : null;
    final suffix = cause == null || cause == 'null' ? '' : ' (cause: $cause)';
    return '${e.code}: ${e.message}$suffix';
  }
}
