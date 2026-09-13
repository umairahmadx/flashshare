import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flashshare/api/storage_client.dart';

// These payloads mirror the live storage.to responses, captured by probing the
// real API. They lock the client's parsing to the actual server contract.

class _FakeApi extends Interceptor {
  final Map<String, Object> responses; // path substring -> decoded body
  _FakeApi(this.responses);

  @override
  void onRequest(RequestOptions o, RequestInterceptorHandler h) {
    final entry = responses.entries.firstWhere((e) => o.path.contains(e.key));
    h.resolve(Response(requestOptions: o, statusCode: 200, data: entry.value));
  }
}

Dio _dio(Map<String, Object> responses) =>
    Dio()..interceptors.add(_FakeApi(responses));

void main() {
  test('uploadConfirm parses the live server response (no raw_url field)',
      () async {
    final client = HttpStorageClient(_dio({
      '/upload/confirm': {
        'success': true,
        'file': {
          'id': 'V7sK5nkRg',
          'url': 'https://storage.to/V7sK5nkRg',
          'filename': 'test.txt',
          'size': 11,
          'human_size': '11 B',
          'expires_at': '2026-09-16T15:01:29+00:00',
        },
        'owner_token': 'owner_v1_abc',
      },
    }), 'vtok');
    final rec = await client.uploadConfirm(
        filename: 'test.txt',
        size: 11,
        contentType: 'text/plain',
        r2Key: 'rk');
    expect(rec.id, 'V7sK5nkRg');
    expect(rec.url, 'https://storage.to/V7sK5nkRg');
    expect(rec.filename, 'test.txt');
    expect(rec.size, 11);
    expect(rec.humanSize, '11 B');
    expect(rec.expiresAt, '2026-09-16T15:01:29+00:00');
    expect(rec.ownerToken, 'owner_v1_abc');
  });

  test('uploadParts parses the live {urls: {"3": ...}} response', () async {
    final client = HttpStorageClient(_dio({
      '/upload/parts': {
        'success': true,
        'urls': {'3': 'https://r2.example/p3', '7': 'https://r2.example/p7'},
      },
    }), 'vtok');
    final urls = await client.uploadParts('uid', [3, 7], 'otok');
    expect(urls, {3: 'https://r2.example/p3', 7: 'https://r2.example/p7'});
  });

  test('a {success:false} body surfaces as StorageException (lock)', () async {
    final client = HttpStorageClient(_dio({
      '/upload/confirm': {
        'success': false,
        'error':
            'Upload incomplete: the file was not found in storage. Please retry the upload.',
      },
    }), 'vtok');
    await expectLater(
      client.uploadConfirm(
          filename: 'x', size: 1, contentType: 'text/plain', r2Key: 'k'),
      throwsA(isA<StorageException>()),
    );
  });
}
