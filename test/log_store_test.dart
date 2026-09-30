import 'package:flutter/foundation.dart';
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

  test('entries survive a reload (persisted), capped at 1000', () async {
    final store = await LogStore.create();
    for (var i = 0; i < 1050; i++) {
      store.info('msg $i');
    }
    // Same instance: capped.
    expect(store.entries.length, 1000);
    expect(store.entries.first.message, 'msg 50');
    // Writes are debounced; flush before reading them back.
    await store.flush();
    // Fresh instance: same data read back from prefs.
    LogStore.resetForTest();
    final store2 = await LogStore.create();
    expect(store2.entries.length, 1000);
    expect(store2.entries.first.message, 'msg 50');
    expect(store2.entries.last.message, 'msg 1049');
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

  test('debug level is recorded and ordered below info', () async {
    final store = await LogStore.create();
    store.debug('tapped tab', source: 'ui.shell');
    expect(store.entries.single.level, LogLevel.debug);
    expect(LogLevel.debug.index < LogLevel.info.index, isTrue);
  });

  test('source tag survives persistence', () async {
    final store = await LogStore.create();
    store.warning('quota fetch failed', source: 'api');
    await store.flush();
    LogStore.resetForTest();
    final restored = await LogStore.create();
    expect(restored.entries.single.source, 'api');
    expect(restored.entries.single.copyText(), contains('[api]'));
  });

  test('old entries without a source field still load', () async {
    SharedPreferences.setMockInitialValues({
      'logs':
          '[{"level":"info","message":"legacy","stack":null,"timestamp":5}]'
    });
    LogStore.resetForTest();
    final store = await LogStore.create();
    expect(store.entries.single.message, 'legacy');
    expect(store.entries.single.source, isNull);
  });

  test('AppLog is a silent no-op before the store exists', () async {
    LogStore.resetForTest();
    expect(() => AppLog.error('too early'), returnsNormally);
    final store = await LogStore.create();
    AppLog.info('now recorded', source: 'test');
    expect(store.entries.last.message, 'now recorded');
    expect(store.entries.last.source, 'test');
  });

  test('recordFlutterError captures framework exceptions with stack',
      () async {
    final store = await LogStore.create();
    store.recordFlutterError(
      FlutterErrorDetails(
        exception: StateError('layout blew up'),
        stack: StackTrace.fromString('#0 RenderBox (box.dart:1)'),
      ),
      context: 'building HistoryScreen',
    );
    final e = store.entries.single;
    expect(e.level, LogLevel.error);
    expect(e.source, 'flutter');
    expect(e.message, contains('building HistoryScreen'));
    expect(e.message, contains('layout blew up'));
    expect(e.stack, contains('box.dart'));
  });
}
