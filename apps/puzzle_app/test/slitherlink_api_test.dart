import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_app/slitherlink_api.dart';
import 'package:puzzle_core/puzzle_core.dart';

void main() {
  test('solves locally when server access is not enabled', () async {
    final puzzle = SlitherlinkPuzzle(
      topology: const GridTopology(rows: 1, columns: 1),
      clues: {const CellId(0, 0): 4},
    );

    final result = await const SlitherlinkApi().solve(
      puzzle,
      puzzle.initialState,
      useServer: false,
    );

    expect(result.hasUniqueSolution, isTrue);
    expect(puzzle.check(result.state).status, CheckStatus.solved);
  });
}
