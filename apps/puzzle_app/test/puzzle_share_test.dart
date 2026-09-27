import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_app/puzzle_share.dart';
import 'package:puzzle_core/puzzle_core.dart';

void main() {
  test('round trips a puzzle including blank cells', () {
    final puzzle = SlitherlinkPuzzle(
      topology: const GridTopology(rows: 3, columns: 4),
      clues: {const CellId(0, 1): 0, const CellId(2, 3): 4},
    );

    final decoded = SlitherlinkShare.decodePuzzle(
      SlitherlinkShare.encodePuzzle(puzzle),
    );

    expect(decoded.topology.rows, 3);
    expect(decoded.topology.columns, 4);
    expect(decoded.clues, puzzle.clues);
  });

  test('round trips line and cross progress', () {
    const topology = GridTopology(rows: 2, columns: 3);
    final state = SlitherlinkState({
      const EdgeId.horizontal(1, 2): SlitherlinkEdgeState.line,
      const EdgeId.vertical(0, 1): SlitherlinkEdgeState.crossed,
    });

    final decoded = SlitherlinkShare.decodeProgress(
      SlitherlinkShare.encodeProgress(state),
      topology,
    );

    expect(decoded.edges, state.edges);
  });

  test('rejects a clue outside the encoded board', () {
    expect(
      () =>
          SlitherlinkShare.decodePuzzle('eyJyIjoxLCJjIjoxLCJuIjpbWzIsMCwzXV19'),
      throwsFormatException,
    );
  });
}
