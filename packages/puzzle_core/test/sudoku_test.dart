import 'package:puzzle_core/puzzle_core.dart';
import 'package:test/test.dart';

void main() {
  test('6x6 validates rows, columns, and 2x3 boxes', () {
    final puzzle = SudokuPuzzle(size: 6, givens: const {});
    final solved = <CellId, int>{
      for (var row = 0; row < 6; row++)
        for (var column = 0; column < 6; column++)
          CellId(row, column): (row * 3 + row ~/ 2 + column) % 6 + 1,
    };
    expect(
      puzzle.check(SudokuState(values: solved)).status,
      CheckStatus.solved,
    );
    final invalid = {...solved, const CellId(0, 0): 2};
    expect(
      puzzle.check(SudokuState(values: invalid)).status,
      CheckStatus.invalid,
    );
  });

  test('9x9 solver completes a classic puzzle with a unique solution', () {
    const rows = [
      '530070000',
      '600195000',
      '098000060',
      '800060003',
      '400803001',
      '700020006',
      '060000280',
      '000419005',
      '000080079',
    ];
    final givens = <CellId, int>{};
    for (var row = 0; row < rows.length; row++) {
      for (var column = 0; column < rows[row].length; column++) {
        final value = int.parse(rows[row][column]);
        if (value != 0) givens[CellId(row, column)] = value;
      }
    }
    final puzzle = SudokuPuzzle(size: 9, givens: givens);
    final result = const SudokuSolver().solve(puzzle);
    expect(result.solutionCount, 1);
    expect(result.state.values, hasLength(81));
    expect(puzzle.check(result.state).status, CheckStatus.solved);
    expect(result.steps, isNotEmpty);
  });

  test('notes and values are undoable puzzle actions', () {
    final puzzle = SudokuPuzzle(size: 6, givens: const {});
    final cell = const CellId(0, 0);
    final session = PuzzleSession<SudokuState, SudokuAction>.start(
      initialState: puzzle.initialState,
      reducer: puzzle.reduce,
    ).apply(SetSudokuNotes(cell, {1, 2}));
    expect(session.state.notesAt(cell), {1, 2});
    final entered = session.apply(SetSudokuValue(cell, 3));
    expect(entered.state.valueAt(cell), 3);
    expect(entered.state.notesAt(cell), isEmpty);
    expect(entered.undo().state.notesAt(cell), {1, 2});
  });

  test('out-of-range values are invalid', () {
    final puzzle = SudokuPuzzle(size: 6, givens: const {});
    expect(
      puzzle.check(SudokuState(values: {const CellId(0, 0): 7})).status,
      CheckStatus.invalid,
    );
  });

  test('generator produces a unique puzzle in each supported size', () {
    for (final size in [6, 9]) {
      final generated = const SudokuGenerator().generate(
        SudokuGenerationOptions(size: size, seed: 82, clueDensity: .65),
      );
      expect(generated.puzzle.givens.length, greaterThan(0));
      expect(const SudokuSolver().countSolutions(generated.puzzle), 1);
      expect(generated.solution.values, hasLength(size * size));
    }
  });

  test('generator matches requested technique-based difficulty', () {
    for (final (size, difficulty) in [
      for (final size in [6, 9])
        for (final difficulty in SudokuDifficulty.values) (size, difficulty),
    ]) {
      final generated = const SudokuGenerator().generate(
        SudokuGenerationOptions(
          size: size,
          difficulty: difficulty,
          seed: 170 + difficulty.index + size,
          clueDensity: .48,
        ),
      );
      final rules = generated.solveResult.steps.map((step) => step.ruleId);
      final usesPair = rules.contains('sudoku.pair');
      final usesAdvanced = rules.any(
        (rule) =>
            rule == 'sudoku.boxLine' ||
            rule == 'sudoku.contradictionElimination' ||
            rule == 'sudoku.contradictionSearch',
      );

      switch (difficulty) {
        case SudokuDifficulty.easy:
          expect(usesPair, isFalse);
          expect(usesAdvanced, isFalse);
        case SudokuDifficulty.medium:
          expect(usesAdvanced, isFalse);
        case SudokuDifficulty.hard:
          expect(
            usesAdvanced,
            isTrue,
            reason:
                'Clues: ${generated.puzzle.givens.length}; '
                'difficulty: $difficulty; rules: ${rules.toSet()}',
          );
      }
      expect(generated.solveResult.solutionCount, 1);
      for (final step in generated.solveResult.steps) {
        expect(step.arguments['scope'], isA<List<Object?>>());
        expect(step.arguments['evidence'], isA<List<Object?>>());
      }
    }
  });
}
