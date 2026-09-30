import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flashshare/models.dart';
import 'package:flashshare/ui/history_screen.dart';

/// Non-thumbable extensions on purpose: the card would otherwise try to fetch
/// a real thumbnail over the network inside a widget test.
HistoryEntry _e({
  required String id,
  required String filename,
  String kind = 'file',
  int size = 2048,
  String? expiresAt,
  int? createdAt,
  bool locked = false,
}) =>
    HistoryEntry(
      id: id,
      url: 'https://storage.to/dl/$id',
      filename: filename,
      size: size,
      expiresAt: expiresAt,
      ownerToken: 'tok',
      kind: kind,
      createdAt: createdAt ??
          DateTime.now().subtract(const Duration(days: 1)).millisecondsSinceEpoch,
      locked: locked,
    );

final _entries = [
  _e(id: 'a', filename: 'notes.txt', size: 1024),
  _e(id: 'b', filename: 'budget.csv', size: 4096, locked: true),
  _e(
      id: 'c',
      filename: 'Bundle',
      kind: 'collection',
      expiresAt: DateTime.now().subtract(const Duration(days: 2)).toIso8601String()),
];

int taps = 0;

Future<void> _pump(WidgetTester tester, List<HistoryEntry> entries) async {
  taps = 0;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: HistoryScreen(
        entries: entries,
        onCopy: (_) => taps++,
        onShare: (_) => taps++,
        onQr: (_) => taps++,
        onEditOptions: (_) => taps++,
        onDelete: (_) => taps++,
        onPick: () => taps++,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders one card per share with its facts', (tester) async {
    await _pump(tester, _entries);
    expect(find.text('notes.txt'), findsOneWidget);
    expect(find.text('budget.csv'), findsOneWidget);
    expect(find.text('Bundle'), findsOneWidget);
    // Honest expiry: the collection expired two days ago.
    expect(find.text('EXPIRED'), findsOneWidget);
    expect(find.text('PASSWORD'), findsOneWidget);
    expect(find.text('COLLECTION'), findsOneWidget);
    expect(find.textContaining('3 shares'), findsOneWidget);
  });

  testWidgets('search narrows the cards', (tester) async {
    await _pump(tester, _entries);
    await tester.enterText(find.byType(TextField), 'budget');
    await tester.pumpAndSettle();
    expect(find.text('budget.csv'), findsOneWidget);
    expect(find.text('notes.txt'), findsNothing);
    expect(find.textContaining('1 of 3 shares'), findsOneWidget);
  });

  testWidgets('kind pills filter files vs collections', (tester) async {
    await _pump(tester, _entries);
    await tester.tap(find.text('FILES'));
    await tester.pumpAndSettle();
    expect(find.text('Bundle'), findsNothing);
    expect(find.text('notes.txt'), findsOneWidget);
    await tester.tap(find.text('COLLECTIONS'));
    await tester.pumpAndSettle();
    expect(find.text('Bundle'), findsOneWidget);
    expect(find.text('notes.txt'), findsNothing);
  });

  testWidgets('category chip filters by file type', (tester) async {
    await _pump(tester, _entries);
    // The category row is a horizontal list — 'TEXT' starts off-screen.
    final categoryRow = find.ancestor(
        of: find.text('ANY TYPE'), matching: find.byType(ListView));
    await tester.drag(categoryRow, const Offset(-320, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TEXT'));
    await tester.pumpAndSettle();
    expect(find.text('notes.txt'), findsOneWidget);
    expect(find.text('budget.csv'), findsNothing);
  });

  testWidgets('no matches offers a reset that restores everything',
      (tester) async {
    await _pump(tester, _entries);
    await tester.enterText(find.byType(TextField), 'zzz-nothing');
    await tester.pumpAndSettle();
    expect(find.text('No shares match these filters'), findsOneWidget);
    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(find.text('notes.txt'), findsOneWidget);
    expect(find.text('Bundle'), findsOneWidget);
  });

  testWidgets('empty library invites the first share', (tester) async {
    await _pump(tester, []);
    expect(find.text('No shares yet'), findsOneWidget);
    await tester.tap(find.text('Share a file'));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('card actions reach the parent', (tester) async {
    await _pump(tester, _entries);
    await tester.tap(find.text('COPY').first);
    await tester.tap(find.text('DELETE').first);
    await tester.pumpAndSettle();
    expect(taps, 2);
  });
}
