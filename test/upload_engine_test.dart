import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flashshare/api/storage_client.dart';
import 'package:flashshare/files/app_file.dart';
import 'package:flashshare/models.dart';
import 'package:flashshare/storage/history_store.dart';
import 'package:flashshare/upload/upload_engine.dart';

// Returns a 200 with a fake etag for every PUT (the R2 step), so the test
// never hits the network.
class FakeR2Interceptor extends Interceptor {
  @override
  void onRequest(RequestOptions o, RequestInterceptorHandler h) {
    h.resolve(Response(
      requestOptions: o,
      statusCode: 200,
      headers: Headers.fromMap({'etag': ['"fake-etag"']}),
    ));
  }
}

class FakeStorageClient implements StorageClient {
  int confirmCalls = 0;
  int createCollectionCalls = 0;
  List<String?> confirmCollectionIds = [];
  int initCalls = 0;

  @override
  Future<UploadInit> uploadInit(String f, String ct, int size) async {
    initCalls++;
    return UploadInit(
      type: 'single',
      uploadUrl: 'https://r2.example/x',
      headers: null,
      r2Key: 'rk-$f',
    );
  }

  @override
  Future<Map<int, String>> uploadParts(u, p, t) async => {};
  @override
  Future<void> uploadCompleteMultipart(u, p, t) async {}
  @override
  Future<void> uploadAbort(u, t) async {}

  @override
  Future<FileRecord> uploadConfirm({
    required String filename,
    required int size,
    required String contentType,
    required String r2Key,
    String? collectionId,
  }) async {
    confirmCalls++;
    confirmCollectionIds.add(collectionId);
    return FileRecord(
      id: 'FQ$confirmCalls',
      url: 'https://storage.to/FQ$confirmCalls',
      rawUrl: 'https://storage.to/r/FQ$confirmCalls',
      filename: filename,
      size: size,
      ownerToken: 'owner_$confirmCalls',
    );
  }

  @override
  Future<Collection> createCollection({int? expectedFileCount}) async {
    createCollectionCalls++;
    return Collection(
        id: 'COL1', url: 'https://storage.to/c/COL1', ownerToken: 'owner_col');
  }

  @override
  Future<void> deleteFile(id, t) async {}
  @override
  Future<void> deleteCollection(id, t) async {}
}

List<AppFile> _tmpFiles(int n) => List.generate(
    n, (i) => BytesFile('fs_test_$i.txt', Uint8List.fromList([1, 2, 3])));

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  Future<UploadEngine> buildEngine(FakeStorageClient c) async => UploadEngine(
      c,
      HistoryStore(await SharedPreferences.getInstance()),
      Dio()..interceptors.add(FakeR2Interceptor()));

  test('separate mode uploads each file once', () async {
    final c = FakeStorageClient();
    await (await buildEngine(c)).enqueue(_tmpFiles(3), UploadMode.separate);
    expect(c.confirmCalls, 3);
    expect(c.confirmCollectionIds.where((x) => x != null), isEmpty);
  });

  test('collection mode creates one collection and attaches all files', () async {
    final c = FakeStorageClient();
    await (await buildEngine(c)).enqueue(_tmpFiles(2), UploadMode.collection);
    expect(c.createCollectionCalls, 1);
    expect(c.confirmCalls, 2);
    expect(c.confirmCollectionIds, everyElement('COL1'));
  });

  test('zip mode produces a single upload', () async {
    final c = FakeStorageClient();
    await (await buildEngine(c)).enqueue(_tmpFiles(2), UploadMode.zip);
    expect(c.confirmCalls, 1);
  });
}
