import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flashshare/ui/home_page.dart';

/// Regression cover for the tab bar blowing up to full screen height.
///
/// `Scaffold` lays out its `bottomNavigationBar` slot with `minHeight: 0` and a
/// maxHeight as tall as the available content. The bar's tab Column used to keep
/// the default `MainAxisSize.max`, so every tab stretched into a screen-tall
/// pill and the body was squeezed to nothing. These tests pin the bar to a
/// compact strip.
Future<void> _pumpBar(
  WidgetTester tester, {
  int index = 0,
  ValueChanged<int>? onChanged,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = const Size(1080, 2220); // 360 x 740 logical
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        body: const Center(child: Text('BODY')),
        bottomNavigationBar:
            BottomNav(index: index, onChanged: onChanged ?? (_) {}),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

double _barHeight(WidgetTester tester) =>
    tester.getSize(find.byType(BottomNav)).height;

void main() {
  testWidgets('tab bar stays a compact strip at the bottom', (tester) async {
    await _pumpBar(tester);
    final bar = tester.getRect(find.byType(BottomNav));
    expect(_barHeight(tester), lessThan(120),
        reason: 'bar stretched to the Scaffold slot instead of its content');
    expect(bar.bottom, closeTo(740, 1));
    // The body keeps almost the whole screen instead of being squeezed out.
    expect(bar.top, greaterThan(600));
  });

  testWidgets('every tab fits on a narrow phone at a large text scale',
      (tester) async {
    await _pumpBar(tester, textScale: 2.5);
    expect(tester.takeException(), isNull);
    expect(find.text('Settings'), findsOneWidget);
    expect(_barHeight(tester), lessThan(160));
  });

  testWidgets('shows the three tabs and reports which one was tapped',
      (tester) async {
    final tapped = <int>[];
    await _pumpBar(tester, onChanged: tapped.add);
    expect(find.text('Send'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(tapped, [1]);
  });

  testWidgets('only the selected tab is a filled pill', (tester) async {
    await _pumpBar(tester, index: 1);
    // Bare MaterialApp falls back to InkPalette.light: accent is ink, the
    // unselected pills are AppColors.transparent.
    final fills = tester
        .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
        .map((c) => (c.decoration as BoxDecoration).color?.toARGB32())
        .toList();
    expect(fills, hasLength(3));
    expect(fills[0], 0x00000000);
    expect(fills[1], 0xFF0A0A0A);
    expect(fills[2], 0x00000000);
  });
}
