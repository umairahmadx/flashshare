import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flashshare/models.dart';

abstract class StorageClient {
  Future<UploadInit> uploadInit(String filename, String contentType, int size);
  Future<Map<int, String>> uploadParts(
      String uploadId, List<int> partNumbers, String ownerToken);
  Future<void> uploadCompleteMultipart(
      String uploadId, List<PartEtag> parts, String ownerToken);
  Future<void> uploadAbort(String uploadId, String ownerToken);
  Future<FileRecord> uploadConfirm({
    required String filename,
    required int size,
    required String contentType,
    required String r2Key,
    String? collectionId,
  });
  Future<Collection> createCollection({int? expectedFileCount});
  Future<void> deleteFile(String id, String ownerToken);
  Future<void> deleteCollection(String id, String ownerToken);

  // Owner-only share settings. Same shape for files and collections.
  Future<void> setPassword(
      String kind, String id, String password, String ownerToken);
  Future<void> removePassword(String kind, String id, String ownerToken);
  Future<void> setExpiry(String kind, String id, int? days, String ownerToken);
  Future<void> setMaxDownloads(
      String kind, String id, int? maxDownloads, String ownerToken);
  Future<void> uploadThumbnail(
      String id, Uint8List bytes, String ownerToken);
  Future<Map<String, dynamic>> bandwidthStatus();
}

class HttpStorageClient implements StorageClient {
  final Dio _dio;
  String visitorToken;
  static const _base = 'https://storage.to/api';

  HttpStorageClient(this._dio, this.visitorToken) {
    _dio.options = BaseOptions(baseUrl: _base, validateStatus: (_) => true);
  }

  Map<String, String> get _visitorHeaders => {
        'X-Visitor-Token': visitorToken,
        'Content-Type': 'application/json',
      };

  Map<String, String> _owner(String t) =>
      {'Authorization': 'Owner $t', 'Content-Type': 'application/json'};

  @override
  Future<UploadInit> uploadInit(String filename, String ct, int size) async {
    final r = await _dio.post('/upload/init',
        options: Options(headers: _visitorHeaders),
        data: {'filename': filename, 'content_type': ct, 'size': size});
    _assertOk(r);
    return UploadInit.fromJson(r.data as Map<String, dynamic>);
  }

  @override
  Future<Map<int, String>> uploadParts(
      String uploadId, List<int> partNumbers, String ownerToken) async {
    final r = await _dio.post('/upload/parts',
        options: Options(headers: _owner(ownerToken)),
        data: {'upload_id': uploadId, 'part_numbers': partNumbers});
    _assertOk(r);
    // Live response: {"success": true, "urls": {"3": "https://..."}}
    final urls = r.data['urls'] as Map;
    return {
      for (var e in urls.entries)
        int.parse(e.key as String): e.value as String
    };
  }

  @override
  Future<void> uploadCompleteMultipart(
      String uploadId, List<PartEtag> parts, String ownerToken) async {
    final r = await _dio.post('/upload/complete-multipart',
        options: Options(headers: _owner(ownerToken)),
        data: {
          'upload_id': uploadId,
          'parts': parts
              .map((p) => {'partNumber': p.partNumber, 'etag': p.etag})
              .toList()
        });
    _assertOk(r);
  }

  @override
  Future<void> uploadAbort(String uploadId, String ownerToken) async {
    final r = await _dio.post('/upload/abort',
        options: Options(headers: _owner(ownerToken)),
        data: {'upload_id': uploadId});
    _assertOk(r);
  }

  @override
  Future<FileRecord> uploadConfirm({
    required String filename,
    required int size,
    required String contentType,
    required String r2Key,
    String? collectionId,
  }) async {
    final body = <String, Object>{
      'filename': filename,
      'size': size,
      'content_type': contentType,
      'r2_key': r2Key,
    };
    if (collectionId != null) body['collection_id'] = collectionId;
    final r = await _dio.post('/upload/confirm',
        options: Options(headers: _visitorHeaders), data: body);
    _assertOk(r);
    return FileRecord.fromJson(
        r.data['file'] as Map<String, dynamic>, r.data['owner_token'] as String);
  }

  @override
  Future<Collection> createCollection({int? expectedFileCount}) async {
    final data = <String, Object>{};
    if (expectedFileCount != null) data['expected_file_count'] = expectedFileCount;
    final r = await _dio.post('/collection',
        options: Options(headers: _visitorHeaders), data: data);
    _assertOk(r);
    return Collection.fromJson(
        r.data['collection'] as Map<String, dynamic>, r.data['owner_token'] as String);
  }

  @override
  Future<void> deleteFile(String id, String ownerToken) async {
    final r = await _dio.delete('/file/$id',
        options: Options(headers: _owner(ownerToken)));
    _assertOk(r);
  }

  @override
  Future<void> deleteCollection(String id, String ownerToken) async {
    final r = await _dio.delete('/collection/$id',
        options: Options(headers: _owner(ownerToken)));
    _assertOk(r);
  }

  // 'file' or 'collection' — the settings endpoints mirror each other exactly,
  // so one private helper serves both.
  String _path(String kind, String id) =>
      kind == 'collection' ? '/collection/$id' : '/file/$id';

  @override
  Future<void> setPassword(
      String kind, String id, String password, String ownerToken) async {
    final r = await _dio.post('${_path(kind, id)}/password',
        options: Options(headers: _owner(ownerToken)),
        data: {'password': password});
    _assertOk(r);
  }

  @override
  Future<void> removePassword(String kind, String id, String ownerToken) async {
    final r = await _dio.delete('${_path(kind, id)}/password',
        options: Options(headers: _owner(ownerToken)));
    _assertOk(r);
  }

  @override
  Future<void> setExpiry(String kind, String id, int? days, String ownerToken) async {
    final r = await _dio.post('${_path(kind, id)}/expiry',
        options: Options(headers: _owner(ownerToken)),
        data: days == null ? {} : {'days': days});
    _assertOk(r);
  }

  @override
  Future<void> setMaxDownloads(
      String kind, String id, int? maxDownloads, String ownerToken) async {
    final r = await _dio.post('${_path(kind, id)}/max-downloads',
        options: Options(headers: _owner(ownerToken)),
        data: maxDownloads == null
            ? {}
            : {'max_downloads': maxDownloads});
    _assertOk(r);
  }

  @override
  Future<void> uploadThumbnail(
      String id, Uint8List bytes, String ownerToken) async {
    final r = await _dio.post('/file/$id/thumbnail',
        options: Options(
          headers: {'Authorization': 'Owner $ownerToken'},
          contentType: 'image/jpeg',
        ),
        data: FormData.fromMap({
          'thumbnail': MultipartFile.fromBytes(bytes, filename: 'thumb.jpg'),
        }));
    _assertOk(r);
  }

  @override
  Future<Map<String, dynamic>> bandwidthStatus() async {
    final r = await _dio.get('/bandwidth/status',
        options: Options(headers: _visitorHeaders));
    _assertOk(r);
    return Map<String, dynamic>.from(r.data as Map);
  }

  void _assertOk(Response r) {
    final data = r.data;
    if (data is Map && data['success'] == false) {
      throw StorageException(
          data['error']?.toString() ?? 'Request failed (${r.statusCode})',
          r.statusCode);
    }
    if (r.statusCode != null && r.statusCode! >= 400) {
      throw StorageException('HTTP ${r.statusCode}', r.statusCode);
    }
  }
}

class StorageException implements Exception {
  final String message;
  final int? statusCode;
  StorageException(this.message, [this.statusCode]);
  @override
  String toString() => 'StorageException($statusCode): $message';
}
