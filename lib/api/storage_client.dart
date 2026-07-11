import 'package:dio/dio.dart';
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
    final list = (r.data['part_urls'] as List).cast<Map<String, dynamic>>();
    return {for (var p in list) p['partNumber'] as int: p['url'] as String};
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
