import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flashshare/logs/log_store.dart';
import 'package:flashshare/ui/logs_screen.dart';

Future<LogStore> _seededStore() async {
  final store = await LogStore.create();
  store.info('upload started');
  store.warning('thumbnail failed');
  store.error('boom', stack: StackTrace.fromString('#0 main (file.dart:42)'));
  return store;
}

Future<void> _pumpScreen(WidgetTester tester, LogStore store) async {
  await tester.pumpWidget(MaterialApp(
    home: LogsScreen(store: store),
  ));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    LogStore.resetForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') return null;
      return null;
    });
  });

  testWidgets('shows all seeded entries with level-colored badges', (tester) async {
    await _pumpScreen(tester, await _seededStore());
    expect(find.text('upload started'), findsOneWidget);
    expect(find.text('thumbnail failed'), findsOneWidget);
    expect(find.text('boom'), findsOneWidget);
  });

  testWidgets('filter chips narrow the list', (tester) async {
    await _pumpScreen(tester, await _seededStore());
    // All -> 3 messages. Errors -> 1.
    expect(find.byType(ListTile), findsNWidgets(3));
    await tester.tap(find.text('Errors'));
    await tester.pumpAndSettle();
    expect(find.text('boom'), findsOneWidget);
    expect(find.text('upload started'), findsNothing);
    expect(find.text('thumbnail failed'), findsNothing);
  });

  testWidgets('tapping an error expands its stack trace', (tester) async {
    await _pumpScreen(tester, await _seededStore());
    expect(find.text('#0 main (file.dart:42)'), findsNothing);
    await tester.tap(find.text('boom'));
    await tester.pumpAndSettle();
    expect(find.text('#0 main (file.dart:42)'), findsOneWidget);
  });

  testWidgets('copy button puts message and stack on the clipboard',
      (tester) async {
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });

    await _pumpScreen(tester, await _seededStore());
    await tester.tap(find.text('boom')); // expand so stack is copyable
    await tester.pumpAndSettle();
    // The error entry is the only tile with onTap (stack entries expand).
    final errorTile = find.byWidgetPredicate(
        (w) => w is ListTile && w.onTap != null);
    await tester
        .tap(find.descendant(of: errorTile, matching: find.byIcon(Icons.copy_outlined)));
    await tester.pumpAndSettle();
    expect(copied, isNotNull);
    expect(copied, contains('boom'));
    expect(copied, contains('#0 main (file.dart:42)'));
  });

  testWidgets('clear button empties the list', (tester) async {
    final store = await _seededStore();
    await _pumpScreen(tester, store);
    await tester.tap(find.byIcon(Icons.delete_sweep_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsNothing);
    expect(store.entries, isEmpty);
  });
}
