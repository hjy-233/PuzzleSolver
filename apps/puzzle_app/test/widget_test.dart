import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_app/main.dart';

void main() {
  testWidgets('shows the Slitherlink player controls', (tester) async {
    await tester.pumpWidget(const PuzzleApp());

    expect(find.text('数回'), findsWidgets);
    expect(find.text('新题'), findsOneWidget);
    expect(find.text('新题设置'), findsOneWidget);
    expect(find.text('棋盘大小'), findsOneWidget);
    expect(find.text('允许空白格'), findsOneWidget);
    expect(find.text('提示'), findsOneWidget);
    expect(find.text('自动解题'), findsOneWidget);
    expect(find.text('检查答案'), findsOneWidget);
  });
}
