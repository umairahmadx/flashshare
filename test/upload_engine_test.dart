import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flashshare/api/storage_client.dart';
import 'package:flashshare/files/app_file.dart';
import 'package:flashshare/models.dart';
import 'package:flashshare/logs/log_store.dart';
import 'package:flashshare/storage/history_store.dart';
import 'package:flashshare/upload/upload_engine.dart';

// Fakes every R2 PUT as a 200 with a fake etag, so the test never hits the
// network. [reject] flips it to fail every PUT with a message-less
// DioException (like a dropped connection) to exercise error reporting.
class FakeR2Interceptor extends Interceptor {
  final bool reject;
  FakeR2Interceptor({this.reject = false});

  @override
  void onRequest(RequestOptions o, RequestInterceptorHandler h) {
    if (reject) {
      // No .message here — mirrors a network-level DioException.
      h.reject(DioException(requestOptions: o));
    } else {
      h.resolve(Response(
        requestOptions: o,
        statusCode: 200,
        headers: Headers.fromMap({'etag': ['"fake-etag"']}),
      ));
    }
  }
}

class FakeStorageClient implements StorageClient {
  int confirmCalls = 0;
  int abortCalls = 0;
  int completeMultipartCalls = 0;
  int createCollectionCalls = 0;
  int initCalls = 0;
  Object? initError; // when set, uploadInit throws
  UploadInit? initOverride; // when set, used instead of the default single init
  final List<String?> confirmCollectionIds = [];

  @override
  Future<UploadInit> uploadInit(String f, String ct, int size) async {
    initCalls++;
    if (initError != null) throw initError!;
    if (initOverride != null) return initOverride!;
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
  Future<void> uploadCompleteMultipart(u, p, t) async {
    completeMultipartCalls++;
  }

  @override
  Future<void> uploadAbort(u, t) async => abortCalls++;

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

  int setPasswordCalls = 0;
  int removePasswordCalls = 0;
  final List<int?> expiryDaysSet = [];
  final List<int?> maxDownloadsSet = [];
  @override
  Future<void> setPassword(kind, id, password, t) async => setPasswordCalls++;
  @override
  Future<void> removePassword(kind, id, t) async => removePasswordCalls++;
  @override
  Future<void> setExpiry(kind, id, days, t) async => expiryDaysSet.add(days);
  @override
  Future<void> setMaxDownloads(kind, id, m, t) async => maxDownloadsSet.add(m);
  @override
  Future<void> uploadThumbnail(id, bytes, t) async {}
  @override
  Future<Map<String, dynamic>> bandwidthStatus() async => {};
}

/// A file whose read fails, to force a zip-build failure.
class ExplodingFile implements AppFile {
  @override
  String get name => 'boom.txt';
  @override
  String? get path => null;
  @override
  Future<int> getSize() async => 3;
  @override
  Future<Uint8List> readAsBytes() async => throw Exception('disk on fire');
  @override
  Future<Uint8List> readRange(int s, int e) async =>
      Uint8List.fromList([1, 2, 3]);
  @override
  Stream<List<int>> openRead([int? s, int? e]) => const Stream.empty();
}

AppFile _f(String name, [int len = 3]) =>
    BytesFile(name, Uint8List.fromList(List.filled(len, 1)));

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  UploadEngine makeEngine(FakeStorageClient c, FakeR2Interceptor r2,
      {void Function()? onIdle}) {
    final e = UploadEngine(c, HistoryStore(prefs), Dio()..interceptors.add(r2));
    if (onIdle != null) e.onIdle = onIdle;
    return e;
  }

  UploadInit multipartInit() => UploadInit(
        type: 'multipart',
        uploadId: 'uid-1',
        r2Key: 'rk-mp',
        partSize: 2,
        totalParts: 2,
        ownerToken: 'otok',
        // Only part 1 is pre-signed; part 2 must be fetched via uploadParts.
        initialUrls: {'1': 'https://r2.example/p1'},
      );

  test('separate mode uploads each file once', () async {
    final c = FakeStorageClient();
    await makeEngine(c, FakeR2Interceptor())
        .enqueue([_f('a.txt'), _f('b.txt'), _f('c.txt')], UploadMode.separate);
    expect(c.confirmCalls, 3);
    expect(c.confirmCollectionIds.where((x) => x != null), isEmpty);
  });

  test('share options are applied after a standalone upload', () async {
    final c = FakeStorageClient();
    await makeEngine(c, FakeR2Interceptor()).enqueue([_f('a.txt')],
        UploadMode.separate,
        options: const ShareOptions(password: 'pass1234', expiryDays: 7, maxDownloads: 3));
    expect(c.setPasswordCalls, 1);
    expect(c.expiryDaysSet, [7]);
    expect(c.maxDownloadsSet, [3]);
  });

  test('collection options are applied once on the collection, not per file',
      () async {
    final c = FakeStorageClient();
    await makeEngine(c, FakeR2Interceptor()).enqueue([_f('a.txt'), _f('b.txt')],
        UploadMode.collection,
        options: const ShareOptions(expiryDays: 5));
    // One expiry call on the collection; files inherit it.
    expect(c.expiryDaysSet, [5]);
    expect(c.setPasswordCalls, 0);
  });

  test('applyOptions removes the password when it was locked and now null',
      () async {
    final c = FakeStorageClient();
    final engine = makeEngine(c, FakeR2Interceptor());
    await engine.enqueue([_f('a.txt')], UploadMode.separate,
        options: const ShareOptions(password: 'pass1234'));
    final locked = HistoryStore(prefs).getAll().single;
    expect(locked.locked, isTrue);
    await engine.applyOptions(locked, const ShareOptions());
    final unlocked = HistoryStore(prefs).getAll().single;
    expect(unlocked.locked, isFalse);
    expect(c.removePasswordCalls, 1);
  });

  test('collection mode creates one collection and attaches all files',
      () async {
    final c = FakeStorageClient();
    await makeEngine(c, FakeR2Interceptor())
        .enqueue([_f('a.txt'), _f('b.txt')], UploadMode.collection);
    expect(c.createCollectionCalls, 1);
    expect(c.confirmCalls, 2);
    expect(c.confirmCollectionIds, everyElement('COL1'));
  });

  test('zip mode produces a single upload', () async {
    final c = FakeStorageClient();
    await makeEngine(c, FakeR2Interceptor())
        .enqueue([_f('a.txt'), _f('b.txt')], UploadMode.zip);
    expect(c.confirmCalls, 1);
  });

  test('a failed multipart upload aborts the server-side upload', () async {
    final c = FakeStorageClient()..initOverride = multipartInit();
    final events = <UploadProgress>[];
    final engine = makeEngine(c, FakeR2Interceptor());
    engine.progress.listen(events.add);
    // Part 2 has no pre-signed URL and uploadParts returns {} — the upload
    // must fail, report an error, and call uploadAbort to clean up R2 state.
    await engine.enqueue([_f('big.bin', 4)], UploadMode.separate);
    await pumpEventQueue();
    expect(c.abortCalls, 1,
        reason: 'a failed multipart must call uploadAbort to clean up');
    expect(c.completeMultipartCalls, 0);
    final err = events.lastWhere((p) => p.state == UploadState.error);
    expect(err.error, isNotNull);
    expect(err.error, isNotEmpty);
  });

  test('cancelling a multipart upload aborts it server-side', () async {
    final c = FakeStorageClient()..initOverride = multipartInit();
    final states = <UploadState>[];
    final engine = makeEngine(c, FakeR2Interceptor());
    // Cancel as soon as the upload is announced (before the first part PUT).
    engine.progress.listen((p) {
      states.add(p.state);
      if (p.state == UploadState.queued) engine.cancel(p.key);
    });
    await engine.enqueue([_f('big.bin', 4)], UploadMode.separate);
    await pumpEventQueue();
    expect(states, contains(UploadState.cancelled));
    expect(states, isNot(contains(UploadState.done)));
    expect(c.abortCalls, 1,
        reason: 'a cancelled multipart must call uploadAbort');
  });

  test('onIdle fires exactly once for a multi-file batch, not per file',
      () async {
    final c = FakeStorageClient();
    var idle = 0;
    await makeEngine(c, FakeR2Interceptor(), onIdle: () => idle++)
        .enqueue([_f('a.txt'), _f('b.txt'), _f('c.txt')], UploadMode.separate);
    expect(idle, 1, reason: 'the service must stop once after the whole batch');
  });

  test('onIdle fires when the zip build fails', () async {
    final c = FakeStorageClient();
    var idle = 0;
    await makeEngine(c, FakeR2Interceptor(), onIdle: () => idle++)
        .enqueue([_f('a.txt'), _f('b.txt'), ExplodingFile()], UploadMode.zip);
    expect(idle, 1, reason: 'a failed zip must still stop the service');
    expect(c.initCalls, 0);
  });

  test('onIdle fires when collection creation fails', () async {
    final c = _ThrowingClient();
    var idle = 0;
    final engine = UploadEngine(c, HistoryStore(prefs),
        Dio()..interceptors.add(FakeR2Interceptor()));
    engine.onIdle = () => idle++;
    await engine.enqueue([_f('a.txt'), _f('b.txt')], UploadMode.collection);
    expect(idle, 1, reason: 'a failed collection create must stop the service');
    expect(c.confirmCalls, 0);
  });

  test('a PUT failure reports a readable error, never a null message',
      () async {
    final c = FakeStorageClient();
    final events = <UploadProgress>[];
    final engine = makeEngine(c, FakeR2Interceptor(reject: true));
    engine.progress.listen(events.add);
    await engine.enqueue([_f('a.txt')], UploadMode.separate);
    await pumpEventQueue();
    final err = events.lastWhere((p) => p.state == UploadState.error);
    expect(err.error, isNotNull,
        reason: 'DioException.message can be null; the tile must not show '
            'an empty "Error: "');
    expect(err.error, isNotEmpty);
  });

  test('failed uploads are written to the log store', () async {
    final c = FakeStorageClient()..initError = StorageException('boom');
    final logStore = await LogStore.create();
    final engine = makeEngine(c, FakeR2Interceptor());
    await engine.enqueue([_f('a.txt')], UploadMode.separate);
    await pumpEventQueue();
    final errors =
        logStore.entries.where((e) => e.level == LogLevel.error);
    expect(errors, isNotEmpty,
        reason: 'an upload failure must land in the log store');
    expect(errors.last.message, contains('boom'));
  });
}

class _ThrowingClient extends FakeStorageClient {
  @override
  Future<Collection> createCollection({int? expectedFileCount}) async {
    throw StateError('server says no');
  }
}
