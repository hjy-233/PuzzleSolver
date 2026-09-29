import '../../interaction/puzzle_action.dart';
import '../../solver/solve_step.dart';
import '../../topology/grid_topology.dart';

/// Technique tiers used to score generated Sudoku puzzles.
/// Easy uses singles only; medium may require pairs; hard needs box-line
/// reductions or contradiction-based reasoning.
enum SudokuDifficulty { easy, medium, hard }

final class SudokuState {
  SudokuState({
    Map<CellId, int> values = const {},
    Map<CellId, Set<int>> notes = const {},
  }) : values = Map.unmodifiable(values),
       notes = Map.unmodifiable({
         for (final entry in notes.entries)
           entry.key: Set<int>.unmodifiable(entry.value),
       });

  final Map<CellId, int> values;
  final Map<CellId, Set<int>> notes;

  int? valueAt(CellId cell) => values[cell];

  Set<int> notesAt(CellId cell) => notes[cell] ?? const {};

  SudokuState withValue(CellId cell, int? value) {
    final nextValues = Map<CellId, int>.from(values);
    final nextNotes = Map<CellId, Set<int>>.from(notes);
    if (value == null) {
      nextValues.remove(cell);
    } else {
      nextValues[cell] = value;
    }
    nextNotes.remove(cell);
    return SudokuState(values: nextValues, notes: nextNotes);
  }

  SudokuState withNotes(CellId cell, Set<int> value) {
    final nextNotes = Map<CellId, Set<int>>.from(notes);
    if (value.isEmpty) {
      nextNotes.remove(cell);
    } else {
      nextNotes[cell] = value;
    }
    return SudokuState(values: values, notes: nextNotes);
  }
}

sealed class SudokuAction implements PuzzleAction {
  const SudokuAction();
}

final class SetSudokuValue extends SudokuAction {
  const SetSudokuValue(this.cell, this.value);

  final CellId cell;
  final int? value;
}

final class SetSudokuNotes extends SudokuAction {
  SetSudokuNotes(this.cell, Set<int> values)
    : values = Set.unmodifiable(values);

  final CellId cell;
  final Set<int> values;
}

final class SudokuPuzzle {
  SudokuPuzzle({required this.size, required Map<CellId, int> givens})
    : givens = Map.unmodifiable(givens),
      boxRows = size == 6 ? 2 : 3,
      boxColumns = size == 6 ? 3 : 3 {
    if (size != 6 && size != 9) {
      throw ArgumentError.value(size, 'size', 'Sudoku supports 6 or 9.');
    }
    for (final entry in givens.entries) {
      if (!_contains(entry.key)) {
        throw ArgumentError.value(
          entry.key,
          'givens',
          'Cell is outside the board.',
        );
      }
      if (entry.value < 1 || entry.value > size) {
        throw ArgumentError.value(
          entry.value,
          'givens',
          'Value is outside 1...$size.',
        );
      }
    }
  }

  final int size;
  final int boxRows;
  final int boxColumns;
  final Map<CellId, int> givens;

  List<CellId> get cells => [
    for (var row = 0; row < size; row++)
      for (var column = 0; column < size; column++) CellId(row, column),
  ];

  List<List<CellId>> get units => [
    for (var row = 0; row < size; row++)
      [for (var column = 0; column < size; column++) CellId(row, column)],
    for (var column = 0; column < size; column++)
      [for (var row = 0; row < size; row++) CellId(row, column)],
    for (var row = 0; row < size; row += boxRows)
      for (var column = 0; column < size; column += boxColumns)
        [
          for (var boxRow = row; boxRow < row + boxRows; boxRow++)
            for (
              var boxColumn = column;
              boxColumn < column + boxColumns;
              boxColumn++
            )
              CellId(boxRow, boxColumn),
        ],
  ];

  SudokuState get initialState => SudokuState(values: givens);

  bool _contains(CellId cell) =>
      cell.row >= 0 &&
      cell.row < size &&
      cell.column >= 0 &&
      cell.column < size;

  SudokuState reduce(SudokuState state, SudokuAction action) {
    switch (action) {
      case SetSudokuValue(:final cell, :final value):
        if (!_contains(cell) ||
            (value != null && (value < 1 || value > size))) {
          throw ArgumentError(
            'Sudoku value action is outside the board range.',
          );
        }
        if (givens.containsKey(cell)) return state;
        return state.withValue(cell, value);
      case SetSudokuNotes(:final cell, :final values):
        if (!_contains(cell) ||
            values.any((value) => value < 1 || value > size)) {
          throw ArgumentError('Sudoku note action is outside the board range.');
        }
        if (givens.containsKey(cell) || state.valueAt(cell) != null) {
          return state;
        }
        return state.withNotes(cell, values);
    }
  }

  SudokuAction? actionFor(
    PuzzleTarget target,
    PointerGesture gesture,
    SudokuState state,
  ) {
    if (target is! CellTarget || !_contains(target.cell)) {
      return null;
    }
    final cell = target.cell;
    if (givens.containsKey(cell)) return null;
    if (gesture == PointerGesture.secondaryTap ||
        gesture == PointerGesture.doubleTap) {
      return SetSudokuValue(cell, null);
    }
    return null;
  }

  CheckResult check(SudokuState state) {
    for (final entry in state.values.entries) {
      if (!_contains(entry.key) || entry.value < 1 || entry.value > size) {
        return const CheckResult(
          CheckStatus.invalid,
          messageKey: 'sudoku.invalidValue',
        );
      }
    }
    for (final entry in givens.entries) {
      if (state.valueAt(entry.key) != entry.value) {
        return const CheckResult(
          CheckStatus.invalid,
          messageKey: 'sudoku.changedGiven',
        );
      }
    }
    for (final unit in units) {
      final seen = <int>{};
      for (final cell in unit) {
        final value = state.valueAt(cell);
        if (value != null && !seen.add(value)) {
          return const CheckResult(
            CheckStatus.invalid,
            messageKey: 'sudoku.duplicateValue',
          );
        }
      }
    }
    if (cells.any((cell) => state.valueAt(cell) == null)) {
      return const CheckResult(CheckStatus.incomplete);
    }
    return const CheckResult(CheckStatus.solved);
  }

  bool isConsistent(Map<CellId, int> values) {
    for (final entry in values.entries) {
      if (!_contains(entry.key) || entry.value < 1 || entry.value > size) {
        return false;
      }
    }
    for (final unit in units) {
      final seen = <int>{};
      for (final cell in unit) {
        final value = values[cell];
        if (value != null && !seen.add(value)) return false;
      }
    }
    return true;
  }
}

typedef SudokuSolveStep = SolveStep<SudokuAction>;
