# Flash Share Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a no-login Flutter app (Android + Web) that uploads files to the storage.to API via its 3-step flow, returns a copyable shareable link, accepts files shared in from the OS share sheet, and tracks uploads locally so the owner can copy links and delete them.

**Architecture:** A `StorageClient` wraps the storage.to REST API (returns typed models). An `UploadEngine` orchestrates init → PUT-to-R2 → confirm, branching on single vs multipart, emitting progress. A `HistoryStore` persists the visitor token + owner tokens in `shared_preferences`. The UI picks files (or receives shared ones) and shows active uploads + history. `dio` provides upload progress for free.

**Tech Stack:** Flutter 3.38 / Dart 3.10, `dio`, `file_picker`, `archive`, `path_provider`, `shared_preferences`, `receive_sharing_intent`.

## Global Constraints

- Platforms: **Android + Web only** (iOS/macOS/Windows/Linux already removed).
- **No login / anonymous uploads only.** No auth UI.
- **Visitor token:** random string generated once, persisted in `shared_preferences`, sent as `X-Visitor-Token` on every request.
- **Owner token:** every `owner_token` from init/confirm must be persisted with its file; delete uses `Authorization: Owner <token>`.
- Base URL: `https://storage.to/api`.
- API error shape: `{ "success": false, "error": "..." }`. Map status codes to user messages (429 → "retry after Ns", 404 → remove from history).
- Multiple files (>1): prompt **separate** vs **zip** vs **collection**. Single file: upload directly.
- `ponytail` ceilings (deferred): no `429` auto-retry/backoff; visitor token is non-crypto random; web share-target may need PWA service-worker polish; no upload-concurrency limit.

---

## File Structure

```
lib/
  main.dart                     # bootstrap: tokens, dio, client, engine, MaterialApp
  models.dart                   # UploadInit, PartEtag, FileRecord, Collection, HistoryEntry, guessContentType
  api/storage_client.dart       # abstract StorageClient + HttpStorageClient (dio)
  upload/upload_engine.dart     # UploadEngine: init→PUT→confirm, multipart, progress, cancel
  storage/history_store.dart    # visitor token + history persistence
  share/share_handler.dart      # receive_sharing_intent wiring
  ui/home_page.dart             # pick button, active list, history list
  ui/upload_tile.dart           # HistoryTile + ActiveTile
  ui/multi_file_dialog.dart     # separate / zip / collection chooser
test/
  models_test.dart              # guessContentType
  history_store_test.dart       # token persistence, add/remove
  upload_engine_test.dart       # branching with fake client + fake R2 interceptor
android/app/src/main/AndroidManifest.xml   # (modify) share intent filters
web/index.html                  # (modify) register service worker
web/manifest.json              # (modify) share_target
web/share_target_sw.js         # (create) web share-target handler
```

---

### Task 1: Add dependencies

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add the six packages (resolves latest compatible versions)**

Run:
```bash
cd flashshare
flutter pub add dio file_picker archive path_provider shared_preferences receive_sharing_intent
```
Expected: `pubspec.yaml` updated, dependencies resolved, no errors.

- [ ] **Step 2: Verify pubspec**

Run: `flutter pub get`
Expected: "Got dependencies."

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore: add dio, file_picker, archive, path_provider, shared_preferences, receive_sharing_intent"
```

---

### Task 2: Models

**Files:**
- Create: `lib/models.dart`
- Test: `test/models_test.dart`

**Interfaces:**
- Produces: `UploadInit`, `PartEtag`, `FileRecord`, `Collection`, `HistoryEntry`, `guessContentType(String)`, `UploadMode`, `UploadState`, `UploadProgress` (last three live in `upload_engine.dart`; see Task 5). This task defines the data classes only.

- [ ] **Step 1: Write the failing test for `guessContentType`**

```dart
// test/models_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flashshare/models.dart';

void main() {
  test('guessContentType maps common extensions', () {
    expect(guessContentType('a.pdf'), 'application/pdf');
    expect(guessContentType('b.PNG'), 'image/png');
    expect(guessContentType('c.mp4'), 'video/mp4');
    expect(guessContentType('d.unknown'), 'application/octet-stream');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models_test.dart`
Expected: FAIL — `Could not resolve package:flashshare/models.dart` (file not created yet).

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/models.dart
import 'dart:convert';

class UploadInit {
  final String type;
  final String? uploadUrl;
  final Map<String, dynamic>? headers;
  final String? uploadId;
  final String r2Key;
  final int? partSize;
  final int? totalParts;
  final Map<String, String>? initialUrls;
  final String? ownerToken;

  UploadInit({
    required this.type,
    this.uploadUrl,
    this.headers,
    this.uploadId,
    required this.r2Key,
    this.partSize,
    this.totalParts,
    this.initialUrls,
    this.ownerToken,
  });

  factory UploadInit.fromJson(Map<String, dynamic> j) {
    final urls = j['initial_urls'];
    return UploadInit(
      type: j['type'] as String,
      uploadUrl: j['upload_url'] as String?,
      headers: j['headers'] as Map<String, dynamic>?,
      uploadId: j['upload_id'] as String?,
      r2Key: j['r2_key'] as String,
      partSize: j['part_size'] as int?,
      totalParts: j['total_parts'] as int?,
      initialUrls: urls == null
          ? null
          : (urls as Map).map((k, v) => MapEntry(int.parse(k), v as String)),
      ownerToken: j['owner_token'] as String?,
    );
  }
}

class PartEtag {
  final int partNumber;
  final String etag;
  PartEtag(this.partNumber, this.etag);
}

class FileRecord {
  final String id;
  final String url;
  final String rawUrl;
  final String filename;
  final int size;
  final String? humanSize;
  final String? expiresAt;
  final String ownerToken;

  FileRecord({
    required this.id,
    required this.url,
    required this.rawUrl,
    required this.filename,
    required this.size,
    this.humanSize,
    this.expiresAt,
    required this.ownerToken,
  });

  factory FileRecord.fromJson(Map<String, dynamic> j, String ownerToken) {
    return FileRecord(
      id: j['id'] as String,
      url: j['url'] as String,
      rawUrl: j['raw_url'] as String,
      filename: j['filename'] as String,
      size: j['size'] as int,
      humanSize: j['human_size'] as String?,
      expiresAt: j['expires_at'] as String?,
      ownerToken: ownerToken,
    );
  }
}

class Collection {
  final String id;
  final String url;
  final String? expiresAt;
  final String ownerToken;

  Collection({
    required this.id,
    required this.url,
    this.expiresAt,
    required this.ownerToken,
  });

  factory Collection.fromJson(Map<String, dynamic> j, String ownerToken) {
    return Collection(
      id: j['id'] as String,
      url: j['url'] as String,
      expiresAt: j['expires_at'] as String?,
      ownerToken: ownerToken,
    );
  }
}

class HistoryEntry {
  final String id;
  final String url;
  final String filename;
  final int size;
  final String? expiresAt;
  final String ownerToken;
  final String kind; // 'file' | 'collection'
  final int createdAt;

  HistoryEntry({
    required this.id,
    required this.url,
    required this.filename,
    required this.size,
    this.expiresAt,
    required this.ownerToken,
    required this.kind,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'filename': filename,
        'size': size,
        'expires_at': expiresAt,
        'owner_token': ownerToken,
        'kind': kind,
        'created_at': createdAt,
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
        id: j['id'] as String,
        url: j['url'] as String,
        filename: j['filename'] as String,
        size: j['size'] as int,
        expiresAt: j['expires_at'] as String?,
        ownerToken: j['owner_token'] as String,
        kind: j['kind'] as String,
        createdAt: j['created_at'] as int,
      );
}

String guessContentType(String filename) {
  final ext = filename.contains('.')
      ? filename.split('.').last.toLowerCase()
      : '';
  const map = {
    'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png',
    'gif': 'image/gif', 'webp': 'image/webp', 'bmp': 'image/bmp',
    'pdf': 'application/pdf', 'txt': 'text/plain', 'md': 'text/markdown',
    'csv': 'text/csv', 'json': 'application/json', 'xml': 'application/xml',
    'mp4': 'video/mp4', 'mov': 'video/quicktime', 'webm': 'video/webm',
    'avi': 'video/x-msvideo', 'mkv': 'video/x-matroska',
    'mp3': 'audio/mpeg', 'wav': 'audio/wav', 'ogg': 'audio/ogg', 'm4a': 'audio/mp4',
    'zip': 'application/zip', 'rar': 'application/x-rar-compressed',
    '7z': 'application/x-7z-compressed', 'tar': 'application/x-tar',
    'doc': 'application/msword',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt': 'application/vnd.ms-powerpoint',
    'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.sresentation',
  };
  return map[ext] ?? 'application/octet-stream';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/models_test.dart`
Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```bash
git add lib/models.dart test/models_test.dart
git commit -m "feat: add data models + content-type guesser"
```

---

### Task 3: History store (visitor token + history)

**Files:**
- Create: `lib/storage/history_store.dart`
- Test: `test/history_store_test.dart`

**Interfaces:**
- Consumes: `HistoryEntry` (Task 2), `shared_preferences`.
- Produces: `HistoryStore` with `getVisitorToken()`, `getAll()`, `add(HistoryEntry)`, `remove(String id)`, `create()`.

- [ ] **Step 1: Write the failing test**

```dart
// test/history_store_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flashshare/storage/history_store.dart';
import 'package:flashshare/models.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  test('visitor token is generated once and persists', () async {
    final store = HistoryStore(await SharedPreferences.getInstance());
    final a = await store.getVisitorToken();
    final b = await store.getVisitorToken();
    expect(a, isNotEmpty);
    expect(a, equals(b));
  });

  test('add then remove round-trips', () async {
    final store = HistoryStore(await SharedPreferences.getInstance());
    final e = HistoryEntry(
      id: 'FQ1', url: 'https://storage.to/FQ1', filename: 'a.txt',
      size: 10, ownerToken: 'owner_x', kind: 'file',
      createdAt: 1,
    );
    await store.add(e);
    expect(store.getAll().length, 1);
    await store.remove('FQ1');
    expect(store.getAll().length, 0);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/history_store_test.dart`
Expected: FAIL — `Could not resolve package:flashshare/storage/history_store.dart`.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/storage/history_store.dart
import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flashshare/models.dart';

class HistoryStore {
  static const _kToken = 'visitor_token';
  static const _kHistory = 'history';
  final SharedPreferences _prefs;

  HistoryStore(this._prefs);

  static Future<HistoryStore> create() async {
    return HistoryStore(await SharedPreferences.getInstance());
  }

  Future<String> getVisitorToken() async {
    var t = _prefs.getString(_kToken);
    if (t == null) {
      t = _genToken();
      await _prefs.setString(_kToken, t);
    }
    return t;
  }

  List<HistoryEntry> getAll() {
    final raw = _prefs.getString(_kHistory);
    if (raw == null) return [];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return list.map(HistoryEntry.fromJson).toList();
  }

  Future<void> add(HistoryEntry e) async {
    final all = getAll();
    all.insert(0, e);
    await _prefs.setString(
        _kHistory, jsonEncode(all.map((x) => x.toJson()).toList()));
  }

  Future<void> remove(String id) async {
    final all = getAll().where((e) => e.id != id).toList();
    await _prefs.setString(
        _kHistory, jsonEncode(all.map((x) => x.toJson()).toList()));
  }

  // ponytail: non-crypto random; fine as an anonymous quota id, not a secret.
  String _genToken() {
    final rnd = Random();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    final ts = DateTime.now().millisecondsSinceEpoch;
    return base64Url.encode([...bytes, ...utf8.encode(ts.toString())]);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/history_store_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/storage/history_store.dart test/history_store_test.dart
git commit -m "feat: persist visitor token + upload history"
```

---

### Task 4: Storage client (API wrapper)

**Files:**
- Create: `lib/api/storage_client.dart`

**Interfaces:**
- Consumes: `UploadInit`, `PartEtag`, `FileRecord`, `Collection` (Task 2), `dio`.
- Produces: `abstract class StorageClient` (interface for tests) with methods used by the engine:
  - `Future<UploadInit> uploadInit(String filename, String contentType, int size)`
  - `Future<Map<int,String>> uploadParts(String uploadId, List<int> partNumbers, String ownerToken)`
  - `Future<void> uploadCompleteMultipart(String uploadId, List<PartEtag> parts, String ownerToken)`
  - `Future<void> uploadAbort(String uploadId, String ownerToken)`
  - `Future<FileRecord> uploadConfirm({required String filename, required int size, required String contentType, required String r2Key, String? collectionId})`
  - `Future<Collection> createCollection({int? expectedFileCount})`
  - `Future<void> deleteFile(String id, String ownerToken)`
  - `Future<void> deleteCollection(String id, String ownerToken)`
  - `class StorageException implements Exception` carrying `message` + optional `statusCode`.

- [ ] **Step 1: Write implementation (no separate test; covered by engine test in Task 5)**

```dart
// lib/api/storage_client.dart
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
    final body = {
      'filename': filename,
      'size': size,
      'content_type': contentType,
      'r2_key': r2Key,
      if (collectionId != null) 'collection_id': collectionId,
    };
    final r = await _dio.post('/upload/confirm',
        options: Options(headers: _visitorHeaders), data: body);
    _assertOk(r);
    return FileRecord.fromJson(
        r.data['file'] as Map<String, dynamic>, r.data['owner_token'] as String);
  }

  @override
  Future<Collection> createCollection({int? expectedFileCount}) async {
    final r = await _dio.post('/collection',
        options: Options(headers: _visitorHeaders),
        data: {
          if (expectedFileCount != null) 'expected_file_count': expectedFileCount
        });
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
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/api/storage_client.dart`
Expected: No issues found.

- [ ] **Step 3: Commit**

```bash
git add lib/api/storage_client.dart
git commit -m "feat: storage.to API client (init/parts/confirm/collection/delete)"
```

---

### Task 5: Upload engine (init → PUT → confirm, multipart, progress)

**Files:**
- Create: `lib/upload/upload_engine.dart`
- Test: `test/upload_engine_test.dart`

**Interfaces:**
- Consumes: `StorageClient` (Task 4), `HistoryStore` (Task 3), `guessContentType` + models (Task 2), `archive`, `path_provider`, `dio`.
- Produces:
  - `enum UploadMode { separate, zip, collection }`
  - `enum UploadState { queued, uploading, confirming, done, error, cancelled }`
  - `class UploadProgress { final String key; final String filename; final UploadState state; final int bytesSent; final int total; final String? url; final String? error; }`
  - `class UploadEngine` with:
    - `UploadEngine(StorageClient client, HistoryStore store, Dio r2)`
    - `Stream<UploadProgress> get progress`
    - `Future<void> enqueue(List<File> files, UploadMode mode)`
    - `StorageClient get client`
    - `void cancel(String key)`

- [ ] **Step 1: Write the failing test**

```dart
// test/upload_engine_test.dart
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flashshare/models.dart';
import 'package:flashshare/api/storage_client.dart';
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

List<File> _tmpFiles(int n) {
  final dir = Directory.systemTemp;
  return List.generate(n, (i) {
    final f = File('${dir.path}/fs_test_$i.txt')..writeAsBytesSync([1, 2, 3]);
    return f;
  });
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  UploadEngine _engine(FakeStorageClient c) =>
      UploadEngine(c, HistoryStore(SharedPreferences.getInstanceSync()), Dio()..interceptors.add(FakeR2Interceptor()));

  test('separate mode uploads each file once', () async {
    final c = FakeStorageClient();
    await _engine(c).enqueue(_tmpFiles(3), UploadMode.separate);
    expect(c.confirmCalls, 3);
    expect(c.confirmCollectionIds.where((x) => x != null), isEmpty);
  });

  test('collection mode creates one collection and attaches all files', () async {
    final c = FakeStorageClient();
    await _engine(c).enqueue(_tmpFiles(2), UploadMode.collection);
    expect(c.createCollectionCalls, 1);
    expect(c.confirmCalls, 2);
    expect(c.confirmCollectionIds, everyElement('COL1'));
  });

  test('zip mode produces a single upload', () async {
    final c = FakeStorageClient();
    await _engine(c).enqueue(_tmpFiles(2), UploadMode.zip);
    expect(c.confirmCalls, 1);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/upload_engine_test.dart`
Expected: FAIL — `Could not resolve package:flashshare/upload/upload_engine.dart`.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/upload/upload_engine.dart
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
  final _progress = StreamController<UploadProgress>.broadcast();
  final _cancellers = <String, CancelToken>{};

  UploadEngine(this._client, this._store, this._r2);

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
    final dir = await getTemporaryDirectory();
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

  Future<void> _putSingle(String url, File file, String ct, int size,
      String key, CancelToken token) async {
    await _r2.put(url,
        data: file.openRead(),
        cancelToken: token,
        options: Options(
          method: 'PUT',
          headers: {'Content-Type': ct},
          contentType: ct,
          contentLength: size,
        ),
        onSendProgress: (s, t) => _emit(UploadProgress(
            key: key,
            filename: key.split(Platform.pathSeparator).last,
            state: UploadState.uploading,
            bytesSent: s,
            total: t)));
  }

  Future<void> _putMultipart(UploadInit init, File file, String ct, int size,
      String key, CancelToken token) async {
    final partSize = init.partSize!;
    final totalParts = init.totalParts!;
    final urls = Map<int, String>.from(init.initialUrls ?? {});
    final parts = <PartEtag>[];
    for (var p = 1; p <= totalParts; p++) {
      var url = urls[p];
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
          options: Options(
            method: 'PUT',
            headers: {'Content-Type': ct},
            contentType: ct,
            contentLength: end - start,
          ),
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/upload_engine_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/upload/upload_engine.dart test/upload_engine_test.dart
git commit -m "feat: upload engine (single + multipart, progress, zip/collection)"
```

---

### Task 6: Multi-file dialog

**Files:**
- Create: `lib/ui/multi_file_dialog.dart`

**Interfaces:**
- Produces: `Future<UploadMode?> MultiFileDialog.show(BuildContext, int count)`.

- [ ] **Step 1: Write implementation**

```dart
// lib/ui/multi_file_dialog.dart
import 'package:flutter/material.dart';
import 'package:flashshare/upload/upload_engine.dart';

class MultiFileDialog {
  static Future<UploadMode?> show(BuildContext context, int count) {
    return showDialog<UploadMode>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Share $count files as…'),
        children: [
          SimpleDialogOption(
            child: const Text('Upload separately'),
            onPressed: () => Navigator.pop(ctx, UploadMode.separate),
          ),
          SimpleDialogOption(
            child: const Text('Zip into one file'),
            onPressed: () => Navigator.pop(ctx, UploadMode.zip),
          ),
          SimpleDialogOption(
            child: const Text('As a collection'),
            onPressed: () => Navigator.pop(ctx, UploadMode.collection),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/ui/multi_file_dialog.dart`
Expected: No issues found.

- [ ] **Step 3: Commit**

```bash
git add lib/ui/multi_file_dialog.dart
git commit -m "feat: multi-file mode chooser (separate/zip/collection)"
```

---

### Task 7: Share-in handler + platform wiring

**Files:**
- Create: `lib/share/share_handler.dart`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `web/index.html`
- Modify: `web/manifest.json`
- Create: `web/share_target_sw.js`

**Interfaces:**
- Produces: `class ShareHandler` with `ShareHandler(void Function(List<File>) onFiles)`, `void init()`, `void dispose()`.

- [ ] **Step 1: Write the handler**

```dart
// lib/share/share_handler.dart
import 'dart:io';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

class ShareHandler {
  final void Function(List<File>) onFiles;
  StreamSubscription? _sub;

  ShareHandler(this.onFiles);

  void init() {
    _sub = ReceiveSharingIntent.instance.getMediaStream().listen((files) {
      if (files.isNotEmpty) {
        onFiles(files.map((m) => File(m.path)).toList());
      }
    });
    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      if (files.isNotEmpty) {
        onFiles(files.map((m) => File(m.path)).toList());
      }
    });
  }

  void dispose() => _sub?.cancel();
}
```

- [ ] **Step 2: Add Android share intent filters**

In `android/app/src/main/AndroidManifest.xml`, inside the existing `<activity ...>` block (after the launcher `<intent-filter>`), add:

```xml
            <intent-filter>
                <action android:name="android.intent.action.SEND" />
                <category android:name="android.intent.category.DEFAULT" />
                <data android:mimeType="*/*" />
            </intent-filter>
            <intent-filter>
                <action android:name="android.intent.action.SEND_MULTIPLE" />
                <category android:name="android.intent.category.DEFAULT" />
                <data android:mimeType="*/*" />
            </intent-filter>
```

- [ ] **Step 3: Register service worker in web/index.html**

Before `</body>` in `web/index.html`, add:

```html
  <script>
    if ('serviceWorker' in navigator) {
      navigator.serviceWorker.register('share_target_sw.js');
    }
  </script>
```

- [ ] **Step 4: Add share_target to web/manifest.json**

In `web/manifest.json`, add this key inside the root JSON object (alongside `"name"`, `"start_url"`, etc.):

```json
  "share_target": {
    "action": "/share-target",
    "method": "POST",
    "enctype": "multipart/form-data",
    "params": {
      "files": [
        { "name": "file", "accept": "*/*" }
      ]
    }
  }
```

- [ ] **Step 5: Create the web share-target service worker**

```js
// web/share_target_sw.js
self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);
  if (url.pathname === '/share-target') {
    event.respondWith((async () => {
      const formData = await event.request.formData();
      const files = formData.getAll('file');
      const channel = new BroadcastChannel('flashshare-share');
      files.forEach((f) => channel.postMessage({ name: f.name, size: f.size }));
      channel.close();
      return Response.redirect('/', 303);
    })());
  }
});
```

> Note (ponytail ceiling): `receive_sharing_intent`'s web handling is version-specific. If incoming web shares don't surface in the app, verify the SW message format against the installed package version's web docs; Android works natively regardless.

- [ ] **Step 6: Verify it compiles**

Run: `flutter analyze lib/share/share_handler.dart`
Expected: No issues found.

- [ ] **Step 7: Commit**

```bash
git add lib/share/share_handler.dart android/app/src/main/AndroidManifest.xml web/index.html web/manifest.json web/share_target_sw.js
git commit -m "feat: share-into-app (Android intent + web share target)"
```

---

### Task 8: Upload tiles (UI)

**Files:**
- Create: `lib/ui/upload_tile.dart`

**Interfaces:**
- Consumes: `HistoryEntry` (Task 2), `UploadProgress` + `UploadState` (Task 5).
- Produces: `HistoryTile` (name, link, copy, delete) and `ActiveTile` (name, progress, cancel).

- [ ] **Step 1: Write implementation**

```dart
// lib/ui/upload_tile.dart
import 'package:flutter/material.dart';
import 'package:flashshare/models.dart';
import 'package:flashshare/upload/upload_engine.dart';

class HistoryTile extends StatelessWidget {
  final HistoryEntry e;
  final VoidCallback onCopy;
  final VoidCallback onDelete;
  const HistoryTile(
      {super.key,
      required this.e,
      required this.onCopy,
      required this.onDelete});

  @override
  Widget build(BuildContext context) => ListTile(
        title: Text(e.filename),
        subtitle: Text(e.url,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(icon: const Icon(Icons.copy), onPressed: onCopy),
            IconButton(
                icon: const Icon(Icons.delete),
                onPressed: onDelete),
          ],
        ),
      );
}

class ActiveTile extends StatelessWidget {
  final UploadProgress p;
  final VoidCallback onCancel;
  const ActiveTile(
      {super.key, required this.p, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final pct = p.total > 0 ? (p.bytesSent / p.total).clamp(0.0, 1.0) : 0.0;
    final label = switch (p.state) {
      UploadState.queued => 'Queued',
      UploadState.uploading => 'Uploading ${(pct * 100).toStringAsFixed(0)}%',
      UploadState.confirming => 'Finalizing…',
      UploadState.done => 'Done',
      UploadState.error => 'Error: ${p.error ?? ""}',
      UploadState.cancelled => 'Cancelled',
    };
    return ListTile(
      title: Text(p.filename),
      subtitle: p.state == UploadState.error || p.state == UploadState.cancelled
          ? Text(label)
          : LinearProgressIndicator(value: p.state == UploadState.queued ? 0 : pct),
      trailing: IconButton(
          icon: const Icon(Icons.close),
          onPressed: p.state == UploadState.done ? null : onCancel),
    );
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/ui/upload_tile.dart`
Expected: No issues found.

- [ ] **Step 3: Commit**

```bash
git add lib/ui/upload_tile.dart
git commit -m "feat: history + active upload tiles"
```

---

### Task 9: Home page

**Files:**
- Create: `lib/ui/home_page.dart`

**Interfaces:**
- Consumes: `HistoryStore` (Task 3), `UploadEngine` (Task 5), `ShareHandler` (Task 7), `MultiFileDialog` (Task 6), `HistoryTile` + `ActiveTile` (Task 8), `file_picker`, `Clipboard` (flutter/services), `ScaffoldMessenger`.

- [ ] **Step 1: Write implementation**

```dart
// lib/ui/home_page.dart
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flashshare/models.dart';
import 'package:flashshare/share/share_handler.dart';
import 'package:flashshare/storage/history_store.dart';
import 'package:flashshare/ui/multi_file_dialog.dart';
import 'package:flashshare/ui/upload_tile.dart';
import 'package:flashshare/upload/upload_engine.dart';

class HomePage extends StatefulWidget {
  final HistoryStore store;
  final UploadEngine engine;
  const HomePage({super.key, required this.store, required this.engine});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<UploadProgress> _active = [];
  List<HistoryEntry> _history = [];
  late final ShareHandler _share;

  @override
  void initState() {
    super.initState();
    _history = widget.store.getAll();
    widget.engine.progress.listen((p) {
      if (!mounted) return;
      setState(() {
        _active.removeWhere((a) => a.key == p.key);
        if (p.state != UploadState.done) _active.add(p);
      });
    });
    _share = ShareHandler((files) => _receive(files));
    _share.init();
  }

  Future<void> _pick() async {
    final res = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (res == null) return;
    final files = res.paths
        .where((p) => p != null)
        .map((p) => File(p!))
        .toList();
    if (files.isNotEmpty) await _receive(files);
  }

  Future<void> _receive(List<File> files) async {
    final mode = files.length > 1
        ? await MultiFileDialog.show(context, files.length)
        : UploadMode.separate;
    if (mode == null) return;
    await widget.engine.enqueue(files, mode);
  }

  Future<void> _delete(HistoryEntry e) async {
    try {
      if (e.kind == 'collection') {
        await widget.engine.client.deleteCollection(e.id, e.ownerToken);
      } else {
        await widget.engine.client.deleteFile(e.id, e.ownerToken);
      }
      await widget.store.remove(e.id);
      if (mounted) setState(() => _history = widget.store.getAll());
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Delete failed: $err')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Flash Share')),
        body: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            ..._active.map((p) => ActiveTile(
                p: p, onCancel: () => widget.engine.cancel(p.key))),
            ..._history.map((e) => HistoryTile(
                  e: e,
                  onCopy: () {
                    Clipboard.setData(ClipboardData(text: e.url));
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('Link copied')));
                  },
                  onDelete: () => _delete(e),
                )),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _pick,
          tooltip: 'Pick files',
          child: const Icon(Icons.upload),
        ),
      );
}
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/ui/home_page.dart`
Expected: No issues found.

- [ ] **Step 3: Commit**

```bash
git add lib/ui/home_page.dart
git commit -m "feat: home page wiring pick/share/history"
```

---

### Task 10: App bootstrap

**Files:**
- Modify: `lib/main.dart`

**Interfaces:**
- Consumes: `HistoryStore.create()` (Task 3), `HttpStorageClient` (Task 4), `UploadEngine` (Task 5), `HomePage` (Task 9), `dio`.

- [ ] **Step 1: Replace main.dart**

```dart
// lib/main.dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flashshare/api/storage_client.dart';
import 'package:flashshare/storage/history_store.dart';
import 'package:flashshare/ui/home_page.dart';
import 'package:flashshare/upload/upload_engine.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await HistoryStore.create();
  final token = await store.getVisitorToken();
  final apiDio = Dio(BaseOptions(
    baseUrl: 'https://storage.to/api',
    validateStatus: (_) => true,
  ));
  final client = HttpStorageClient(apiDio, token);
  final r2Dio = Dio(BaseOptions(validateStatus: (_) => true));
  final engine = UploadEngine(client, store, r2Dio);
  runApp(FlashShareApp(store: store, engine: engine));
}

class FlashShareApp extends StatelessWidget {
  final HistoryStore store;
  final UploadEngine engine;
  const FlashShareApp(
      {super.key, required this.store, required this.engine});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Flash Share',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange),
          useMaterial3: true,
        ),
        home: HomePage(store: store, engine: engine),
      );
}
```

- [ ] **Step 2: Analyze full project**

Run: `flutter analyze`
Expected: No issues found.

- [ ] **Step 3: Commit**

```bash
git add lib/main.dart
git commit -m "feat: bootstrap app with client + engine"
```

---

### Task 11: Full verification + run

**Files:**
- None new.

- [ ] **Step 1: Run all tests**

Run: `flutter test`
Expected: All tests pass (models 1, history 2, engine 3).

- [ ] **Step 2: Analyze**

Run: `flutter analyze`
Expected: No issues found.

- [ ] **Step 3: Build Android (smoke)**

Run: `flutter build apk --debug`
Expected: Build succeeds.

- [ ] **Step 4: Commit final state (if any formatting changes)**

```bash
git add -A
git commit -m "chore: final verification pass" || echo "nothing to commit"
```

---

## Self-Review

**1. Spec coverage**
- Upload 3-step flow (init/PUT/confirm) → Task 4 + 5 ✓
- Multipart + progress → Task 5 ✓
- Single vs multipart branching → Task 5 (`init.type`) ✓
- Visitor token persist + send → Task 3 + 10 ✓
- Owner token persist + delete → Task 5 (store), Task 9 (delete) ✓
- Multiple files → dialog separate/zip/collection → Task 6 + 9 ✓
- Zip build → Task 5 (`_buildZip`) ✓
- Collection → Task 5 + 4 (`createCollection`) ✓
- Share-in Android + Web → Task 7 ✓
- Copy link + history UI → Task 8 + 9 ✓
- Errors mapped → Task 4 (`_assertOk`/`StorageException`) ✓
- Tests for token/history/branching → Task 2/3/5 ✓
- Skipped (per spec, deferred): password/expiry UI, thumbnails, batch, bandwidth, 429 backoff, web share-target polish ✓

**2. Placeholder scan** — No TBD/TODO/"similar to" found. All code steps show concrete code. The only prose caveat is the web SW version note (a spec-approved ceiling, not a placeholder).

**3. Type consistency**
- `StorageClient` method signatures match between abstract (Task 4), `HttpStorageClient` (Task 4), `FakeStorageClient` (Task 5 test), and call sites in `UploadEngine` (Task 5) and `HomePage._delete` (Task 9). ✓
- `UploadInit` fields (`uploadUrl`, `r2Key`, `initialUrls`, `ownerToken`, `partSize`, `totalParts`, `uploadId`) used consistently in Task 5. ✓
- `UploadProgress`/`UploadState` consumed in Task 8 exactly as produced in Task 5. ✓
- `HistoryEntry` fields consumed in Task 8/9 match those written in Task 3/5. ✓
- `guessContentType` signature identical in Task 2 (def) and Task 5 (use). ✓
