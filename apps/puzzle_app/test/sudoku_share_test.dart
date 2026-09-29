import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_app/puzzle_share.dart';
import 'package:puzzle_core/puzzle_core.dart';

void main() {
  test('round-trips a puzzle, entered values, and candidate notes', () {
    final puzzle = SudokuPuzzle(
      size: 6,
      givens: {const CellId(0, 0): 1, const CellId(5, 5): 6},
    );
    final decodedPuzzle = SudokuShare.decodePuzzle(
      SudokuShare.encodePuzzle(puzzle),
    );
    final state = SudokuState(
      values: {...puzzle.givens, const CellId(0, 1): 2},
      notes: {
        const CellId(0, 2): {3, 4},
      },
    );
    final decodedState = SudokuShare.decodeProgress(
      SudokuShare.encodeProgress(state),
      decodedPuzzle,
    );
    expect(decodedPuzzle.givens, puzzle.givens);
    expect(decodedState.values, state.values);
    expect(decodedState.notes, state.notes);
  });
}
