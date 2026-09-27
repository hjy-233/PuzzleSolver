import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:puzzle_app/main.dart';

void main() {
  testWidgets('shows the Slitherlink player controls', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const PuzzleApp());

    expect(find.text('数回'), findsWidgets);
    expect(find.text('新题'), findsOneWidget);
    expect(find.text('新题设置'), findsOneWidget);
    expect(find.text('高（行）'), findsOneWidget);
    expect(find.text('宽（列）'), findsOneWidget);
    expect(find.text('允许空白格'), findsOneWidget);
    expect(find.text('提示'), findsOneWidget);
    expect(find.text('自动解题'), findsOneWidget);
    expect(find.text('检查答案'), findsOneWidget);
  });

  testWidgets('portrait layout keeps the reasoning section reachable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const PuzzleApp());

    final stepsHeading = find.text('推理步骤 0');
    await tester.drag(find.byType(ListView).first, const Offset(0, -1200));
    await tester.pumpAndSettle();

    expect(stepsHeading, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
