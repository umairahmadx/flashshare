import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flashshare/logs/log_store.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    LogStore.resetForTest();
  });

  test('logs at each level are stored with level and timestamp', () async {
    final store = await LogStore.create();
    store.info('upload started');
    store.warning('thumbnail failed');
    store.error('boom', stack: StackTrace.current);
    final all = store.entries;
    expect(all.map((e) => e.level),
        [LogLevel.info, LogLevel.warning, LogLevel.error]);
    expect(all.first.message, 'upload started');
    expect(all.every((e) => e.timestamp > 0), isTrue);
  });

  test('error entries keep their stack trace; others have none', () async {
    final store = await LogStore.create();
    final st = StackTrace.current;
    store.error('boom', stack: st);
    store.info('fine');
    expect(store.entries.first.stack, st.toString());
    expect(store.entries.last.stack, isNull);
  });

  test('entries survive a reload (persisted), capped at 200', () async {
    final store = await LogStore.create();
    for (var i = 0; i < 250; i++) {
      store.info('msg $i');
    }
    // Same instance: capped.
    expect(store.entries.length, 200);
    expect(store.entries.first.message, 'msg 50');
    // Fresh instance: same data read back from prefs.
    final store2 = await LogStore.create();
    expect(store2.entries.length, 200);
    expect(store2.entries.first.message, 'msg 50');
    expect(store2.entries.last.message, 'msg 249');
  });

  test('UI is notified on add and on clear', () async {
    final store = await LogStore.create();
    var notified = 0;
    store.addListener(() => notified++);
    store.info('a');
    store.clear();
    expect(notified, 2);
    expect(store.entries, isEmpty);
  });

  test('copyText formats message plus stack', () async {
    final e = LogEntry(
        level: LogLevel.error,
        message: 'boom',
        stack: 'line1\nline2',
        timestamp: DateTime(2026, 9, 13, 10, 30).millisecondsSinceEpoch);
    expect(e.copyText(), contains('boom'));
    expect(e.copyText(), contains('line1'));
    expect(e.copyText(), contains('line2'));
    final plain = LogEntry(
        level: LogLevel.info, message: 'ok', timestamp: 1);
    expect(plain.copyText(), contains('ok'));
    expect(plain.copyText(), isNot(contains('Stack')));
  });
}
