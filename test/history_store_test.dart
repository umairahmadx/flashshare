import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flashshare/models.dart';
import 'package:flashshare/storage/history_store.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
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
      id: 'FQ1',
      url: 'https://storage.to/FQ1',
      filename: 'a.txt',
      size: 10,
      ownerToken: 'owner_x',
      kind: 'file',
      createdAt: 1,
    );
    await store.add(e);
    expect(store.getAll().length, 1);
    await store.remove('FQ1');
    expect(store.getAll().length, 0);
  });
}
