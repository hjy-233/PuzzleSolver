import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:puzzle_app/main.dart';
import 'package:puzzle_core/puzzle_core.dart';

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
    final initialDensity = tester.widget<Slider>(find.byType(Slider)).value;
    await tester.tap(find.text('困难'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SegmentedButton<PuzzleDifficulty>>(
            find.byType(SegmentedButton<PuzzleDifficulty>),
          )
          .selected,
      {PuzzleDifficulty.hard},
    );
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
    await tester.drag(find.byType(Slider), const Offset(90, 0));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Slider>(find.byType(Slider)).value,
      greaterThan(initialDensity),
    );
    expect(find.text('宽（列）'), findsOneWidget);
    expect(find.text('允许空白格'), findsOneWidget);
    expect(find.text('提示'), findsOneWidget);
    expect(find.text('自动解题'), findsOneWidget);
    expect(find.text('检查答案'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byTooltip('放大棋盘'), findsOneWidget);
    expect(find.byTooltip('缩小棋盘'), findsOneWidget);
  });

  testWidgets('portrait layout stays fixed and opens puzzle/settings sheets', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const PuzzleApp());

    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.text('自动解题'), findsOneWidget);
    expect(find.text('检查'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.byType(ListView), findsNothing);
    expect(find.byTooltip('放大棋盘'), findsOneWidget);
    final boardViewer = find.byType(InteractiveViewer);
    final transformationController = tester
        .widget<InteractiveViewer>(boardViewer)
        .transformationController!;
    await tester.tap(find.byTooltip('放大棋盘'));
    await tester.pumpAndSettle();
    expect(transformationController.value.getMaxScaleOnAxis(), greaterThan(1));

    await tester.tap(find.byTooltip('选择谜题'));
    await tester.pumpAndSettle();
    expect(find.text('谜题库'), findsOneWidget);
    await tester.tap(
      find.ancestor(
        of: find.byIcon(Icons.route_outlined),
        matching: find.byType(ListTile),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.text('新题设置'), findsOneWidget);
    expect(find.text('高（行）'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile app bar keeps common actions visible when they fit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(667, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const PuzzleApp());

    expect(find.byTooltip('分享'), findsOneWidget);
    expect(find.byTooltip('新题'), findsOneWidget);
    expect(find.byTooltip('撤销'), findsOneWidget);
    expect(find.byTooltip('重做'), findsOneWidget);
    expect(find.byTooltip('更多操作'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('very narrow app bar moves only hidden history actions to menu', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const PuzzleApp());

    expect(find.byTooltip('分享'), findsOneWidget);
    expect(find.byTooltip('新题'), findsOneWidget);
    expect(find.byTooltip('撤销'), findsNothing);
    expect(find.byTooltip('重做'), findsNothing);
    expect(find.byTooltip('更多操作'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
