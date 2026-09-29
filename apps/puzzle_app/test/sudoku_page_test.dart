import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_app/sudoku_page.dart';
import 'package:puzzle_core/puzzle_core.dart';

void main() {
  testWidgets('mobile Sudoku page exposes input, notes, and settings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: SudokuPage()));
    expect(find.text('数独'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.text('候选笔记'), findsOneWidget);
    expect(find.byTooltip('自动解题'), findsOneWidget);
    expect(find.byTooltip('设置'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile settings update their selected state immediately', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: SudokuPage()));
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('困难'));
    await tester.pump();

    final selector = tester.widget<SegmentedButton<SudokuDifficulty>>(
      find.byType(SegmentedButton<SudokuDifficulty>),
    );
    expect(selector.selected, {SudokuDifficulty.hard});
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop Sudoku uses keyboard input without a number pad', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: SudokuPage()));
    expect(find.widgetWithText(TextButton, '1'), findsNothing);
    expect(find.byTooltip('重置棋盘缩放'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
