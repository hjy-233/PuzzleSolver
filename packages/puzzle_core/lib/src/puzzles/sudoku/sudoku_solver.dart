import 'dart:math';

import '../../generation/puzzle_generator.dart';
import '../../interaction/puzzle_action.dart';
import '../../topology/grid_topology.dart';
import 'sudoku.dart';

final class SudokuSolveResult {
  const SudokuSolveResult({
    required this.state,
    required this.steps,
    required this.solutionCount,
  });

  final SudokuState state;
  final List<SudokuSolveStep> steps;
  final int solutionCount;

  bool get hasUniqueSolution => solutionCount == 1;
}

final class SudokuGenerationOptions implements PuzzleGenerationOptions {
  const SudokuGenerationOptions({
    required this.size,
    this.difficulty = SudokuDifficulty.medium,
    this.clueDensity = .42,
    this.seed,
  });

  final int size;
  final SudokuDifficulty difficulty;
  final double clueDensity;
  final int? seed;
}

final class GeneratedSudokuPuzzle {
  const GeneratedSudokuPuzzle({
    required this.puzzle,
    required this.solution,
    required this.solveResult,
  });

  final SudokuPuzzle puzzle;
  final SudokuState solution;
  final SudokuSolveResult solveResult;
}

/// Constraint solver with human-readable singles, pairs and box-line steps.
final class SudokuSolver {
  const SudokuSolver();

  SudokuSolveResult solve(SudokuPuzzle puzzle, {SudokuState? initialState}) {
    final values = <CellId, int>{...puzzle.givens, ...?initialState?.values};
    if (!puzzle.isConsistent(values)) {
      return SudokuSolveResult(
        state: SudokuState(values: values),
        steps: const [],
        solutionCount: 0,
      );
    }
    final count = countSolutions(puzzle, initialValues: values, limit: 2);
    if (count == 0) {
      return SudokuSolveResult(
        state: SudokuState(values: values),
        steps: const [],
        solutionCount: 0,
      );
    }
    final steps = <SudokuSolveStep>[];
    final notes = <CellId, Set<int>>{...?initialState?.notes};
    var working = Map<CellId, int>.from(values);
    var logicalCandidates = candidatesFor(puzzle, working);
    final answer = _firstSolution(puzzle, working);
    if (answer == null) {
      return SudokuSolveResult(
        state: SudokuState(values: working),
        steps: const [],
        solutionCount: 0,
      );
    }

    while (working.length < puzzle.size * puzzle.size) {
      final deduction = _findDeduction(puzzle, working, logicalCandidates);
      if (deduction != null) {
        steps.add(deduction.step);
        for (final action in deduction.step.actions) {
          switch (action) {
            case SetSudokuValue(:final cell, :final value):
              if (value != null) working[cell] = value;
              notes.remove(cell);
              logicalCandidates = _preserveEliminations(
                candidatesFor(puzzle, working),
                logicalCandidates,
              );
            case SetSudokuNotes(:final cell, :final values):
              notes[cell] = values;
              logicalCandidates[cell] = {...values};
          }
        }
        continue;
      }

      var eliminatedCandidate = false;
      for (final entry in logicalCandidates.entries) {
        if (entry.value.length < 2) continue;
        for (final candidate in entry.value.toList()..sort()) {
          final trial = {...working, entry.key: candidate};
          if (countSolutions(puzzle, initialValues: trial, limit: 1) != 0) {
            continue;
          }
          final remaining = {...entry.value}..remove(candidate);
          final step = SudokuSolveStep(
            ruleId: 'sudoku.contradictionElimination',
            highlights: [CellTarget(entry.key)],
            actions: [SetSudokuNotes(entry.key, remaining)],
            arguments: {
              'value': candidate,
              'removed': 1,
              'scope': _cellsData([entry.key]),
              'evidence': _cellsData([entry.key]),
              'changes': _cellsData([entry.key]),
            },
          );
          steps.add(step);
          logicalCandidates[entry.key] = remaining;
          notes[entry.key] = remaining;
          eliminatedCandidate = true;
          break;
        }
        if (eliminatedCandidate) break;
      }
      if (eliminatedCandidate) continue;

      final cell = mostConstrainedCell(puzzle, working, logicalCandidates);
      if (cell == null) break;
      final value = answer[cell];
      if (value == null) break;
      steps.add(
        SudokuSolveStep(
          ruleId: 'sudoku.contradictionSearch',
          highlights: [CellTarget(cell)],
          actions: [SetSudokuValue(cell, value)],
          arguments: {
            'value': value,
            'scope': _cellsData([cell]),
            'evidence': _cellsData([cell]),
            'changes': _cellsData([cell]),
          },
        ),
      );
      working[cell] = value;
      notes.remove(cell);
    }
    return SudokuSolveResult(
      state: SudokuState(values: working, notes: notes),
      steps: List.unmodifiable(steps),
      solutionCount: count,
    );
  }

  SudokuSolveStep? hint(SudokuPuzzle puzzle, SudokuState state) {
    final values = <CellId, int>{...puzzle.givens, ...state.values};
    if (!puzzle.isConsistent(values)) return null;
    return _findDeduction(puzzle, values, candidatesFor(puzzle, values))?.step;
  }

  int countSolutions(
    SudokuPuzzle puzzle, {
    Map<CellId, int> initialValues = const {},
    int limit = 2,
  }) {
    final values = <CellId, int>{...puzzle.givens, ...initialValues};
    if (!puzzle.isConsistent(values)) return 0;
    return _search(puzzle, values, limit: limit, firstSolution: null);
  }

  int _search(
    SudokuPuzzle puzzle,
    Map<CellId, int> values, {
    required int limit,
    required Map<CellId, int>? firstSolution,
  }) {
    var count = 0;
    final pending = <Map<CellId, int>>[Map.from(values)];
    while (pending.isNotEmpty && count < limit) {
      final current = pending.removeLast();
      final candidates = candidatesFor(puzzle, current);
      if (candidates.values.any((set) => set.isEmpty)) continue;
      if (current.length == puzzle.size * puzzle.size) {
        count++;
        if (firstSolution != null && firstSolution.isEmpty) {
          firstSolution.addAll(current);
        }
        continue;
      }
      final cell = mostConstrainedCell(puzzle, current, candidates);
      if (cell == null) continue;
      final options = candidates[cell]!.toList()..sort();
      for (final value in options.reversed) {
        pending.add({...current, cell: value});
      }
    }
    return count;
  }

  Map<CellId, int>? _firstSolution(
    SudokuPuzzle puzzle,
    Map<CellId, int> values,
  ) {
    final working = Map<CellId, int>.from(values);
    if (!puzzle.isConsistent(working)) return null;
    final candidates = candidatesFor(puzzle, working);
    if (candidates.values.any((set) => set.isEmpty)) return null;
    if (working.length == puzzle.size * puzzle.size) return working;
    final cell = mostConstrainedCell(puzzle, working, candidates);
    if (cell == null) return null;
    for (final value in candidates[cell]!) {
      final solution = _firstSolution(puzzle, {...working, cell: value});
      if (solution != null) return solution;
    }
    return null;
  }

  Map<CellId, Set<int>> candidatesFor(
    SudokuPuzzle puzzle,
    Map<CellId, int> values,
  ) {
    final result = <CellId, Set<int>>{};
    for (final cell in puzzle.cells) {
      if (values.containsKey(cell)) continue;
      final used = <int>{};
      for (final unit in puzzle.units) {
        if (unit.contains(cell)) {
          used.addAll([
            for (final peer in unit)
              if (values[peer] != null) values[peer]!,
          ]);
        }
      }
      result[cell] = {
        for (var value = 1; value <= puzzle.size; value++)
          if (!used.contains(value)) value,
      };
    }
    return result;
  }

  CellId? mostConstrainedCell(
    SudokuPuzzle puzzle,
    Map<CellId, int> values,
    Map<CellId, Set<int>> candidates,
  ) {
    CellId? best;
    var bestCount = puzzle.size + 1;
    for (final cell in puzzle.cells) {
      if (values.containsKey(cell)) continue;
      final count = candidates[cell]?.length ?? 0;
      if (count < bestCount) {
        best = cell;
        bestCount = count;
      }
    }
    return best;
  }

  _Deduction? _findDeduction(
    SudokuPuzzle puzzle,
    Map<CellId, int> values,
    Map<CellId, Set<int>> candidates,
  ) {
    // Naked single.
    for (final entry in candidates.entries) {
      if (entry.value.length == 1) {
        final value = entry.value.single;
        final evidence = _filledPeers(
          puzzle,
          values,
          entry.key,
        ).where((cell) => values[cell] != value).toSet();
        return _Deduction(
          SudokuSolveStep(
            ruleId: 'sudoku.nakedSingle',
            highlights: [
              CellTarget(entry.key),
              ...evidence.map(CellTarget.new),
            ],
            actions: [SetSudokuValue(entry.key, value)],
            arguments: {
              'value': value,
              'evidence': _cellsData(evidence),
              'scope': _cellsData([entry.key]),
            },
          ),
        );
      }
    }

    // Hidden single.
    for (var unitIndex = 0; unitIndex < puzzle.units.length; unitIndex++) {
      final unit = puzzle.units[unitIndex];
      for (var value = 1; value <= puzzle.size; value++) {
        final cells = unit
            .where((cell) => candidates[cell]?.contains(value) ?? false)
            .toList();
        if (cells.length == 1) {
          final target = cells.single;
          final evidence = <CellId>{};
          for (final other in unit) {
            if (other == target || values.containsKey(other)) continue;
            evidence.addAll(
              _filledPeers(
                puzzle,
                values,
                other,
              ).where((cell) => values[cell] == value),
            );
          }
          return _Deduction(
            SudokuSolveStep(
              ruleId: 'sudoku.hiddenSingle',
              highlights: [
                CellTarget(target),
                ...unit.map(CellTarget.new),
                ...evidence.map(CellTarget.new),
              ],
              actions: [SetSudokuValue(target, value)],
              arguments: {
                'value': value,
                'unit': _unitName(puzzle, unitIndex),
                'scope': _cellsData(unit),
                'evidence': _cellsData(evidence),
              },
            ),
          );
        }
      }
    }

    // Naked pairs remove two values from the other cells in a unit.
    for (final unit in puzzle.units) {
      final pairs = <String, List<CellId>>{};
      for (final cell in unit) {
        final options = candidates[cell];
        if (options?.length == 2) {
          final key = (options!.toList()..sort()).join(',');
          pairs.putIfAbsent(key, () => []).add(cell);
        }
      }
      for (final entry in pairs.entries) {
        if (entry.value.length != 2) continue;
        final valuesToRemove = entry.key.split(',').map(int.parse).toSet();
        final removals = <CellId, Set<int>>{};
        for (final cell in unit) {
          if (entry.value.contains(cell)) continue;
          final options = candidates[cell];
          if (options == null) continue;
          final overlap = options.intersection(valuesToRemove);
          if (overlap.isNotEmpty) removals[cell] = overlap;
        }
        if (removals.isNotEmpty) {
          return _Deduction(
            _candidateRemovalStep(
              'sudoku.pair',
              null,
              removals,
              candidates,
              entry.value,
              arguments: {
                'pair': valuesToRemove.toList()..sort(),
                'scope': _cellsData(unit),
              },
            ),
          );
        }
      }
    }

    // Locked candidates: a value confined to one box row/column can be
    // removed from the rest of that row/column.
    for (final box in puzzle.units.skip(puzzle.size * 2)) {
      for (var value = 1; value <= puzzle.size; value++) {
        final possible = box
            .where((cell) => candidates[cell]?.contains(value) ?? false)
            .toList();
        if (possible.length < 2) continue;
        final rows = possible.map((cell) => cell.row).toSet();
        final columns = possible.map((cell) => cell.column).toSet();
        final removals = <CellId, Set<int>>{};
        if (rows.length == 1) {
          final row = rows.single;
          for (final cell in puzzle.units[row]) {
            if (!box.contains(cell) &&
                (candidates[cell]?.contains(value) ?? false)) {
              removals[cell] = {...?removals[cell], value};
            }
          }
        }
        if (columns.length == 1) {
          final column = columns.single;
          for (final cell in puzzle.units[puzzle.size + column]) {
            if (!box.contains(cell) &&
                (candidates[cell]?.contains(value) ?? false)) {
              removals[cell] = {...?removals[cell], value};
            }
          }
        }
        if (removals.isNotEmpty) {
          return _Deduction(
            _candidateRemovalStep(
              'sudoku.boxLine',
              value,
              removals,
              candidates,
              possible,
              arguments: {'scope': _cellsData(box)},
            ),
          );
        }
      }
    }

    // Claiming: candidates confined to one box inside a row/column are
    // removed from the rest of that box.
    for (var row = 0; row < puzzle.size; row++) {
      final unit = puzzle.units[row];
      for (var value = 1; value <= puzzle.size; value++) {
        final possible = unit
            .where((cell) => candidates[cell]?.contains(value) ?? false)
            .toList();
        if (possible.length < 2) continue;
        final boxRow = possible.first.row ~/ puzzle.boxRows;
        final boxColumn = possible.first.column ~/ puzzle.boxColumns;
        if (possible.any(
          (cell) =>
              cell.row ~/ puzzle.boxRows != boxRow ||
              cell.column ~/ puzzle.boxColumns != boxColumn,
        )) {
          continue;
        }
        final box = puzzle.units
            .skip(puzzle.size * 2)
            .firstWhere(
              (cells) =>
                  cells.first.row ~/ puzzle.boxRows == boxRow &&
                  cells.first.column ~/ puzzle.boxColumns == boxColumn,
            );
        final removals = <CellId, Set<int>>{
          for (final cell in box)
            if (cell.row != row && (candidates[cell]?.contains(value) ?? false))
              cell: {value},
        };
        if (removals.isNotEmpty) {
          return _Deduction(
            _candidateRemovalStep(
              'sudoku.boxLine',
              value,
              removals,
              candidates,
              possible,
              arguments: {
                'scope': _cellsData([...unit, ...box]),
              },
            ),
          );
        }
      }
    }
    for (var column = 0; column < puzzle.size; column++) {
      final unit = puzzle.units[puzzle.size + column];
      for (var value = 1; value <= puzzle.size; value++) {
        final possible = unit
            .where((cell) => candidates[cell]?.contains(value) ?? false)
            .toList();
        if (possible.length < 2) continue;
        final boxRow = possible.first.row ~/ puzzle.boxRows;
        final boxColumn = possible.first.column ~/ puzzle.boxColumns;
        if (possible.any(
          (cell) =>
              cell.row ~/ puzzle.boxRows != boxRow ||
              cell.column ~/ puzzle.boxColumns != boxColumn,
        )) {
          continue;
        }
        final box = puzzle.units
            .skip(puzzle.size * 2)
            .firstWhere(
              (cells) =>
                  cells.first.row ~/ puzzle.boxRows == boxRow &&
                  cells.first.column ~/ puzzle.boxColumns == boxColumn,
            );
        final removals = <CellId, Set<int>>{
          for (final cell in box)
            if (cell.column != column &&
                (candidates[cell]?.contains(value) ?? false))
              cell: {value},
        };
        if (removals.isNotEmpty) {
          return _Deduction(
            _candidateRemovalStep(
              'sudoku.boxLine',
              value,
              removals,
              candidates,
              possible,
              arguments: {
                'scope': _cellsData([...unit, ...box]),
              },
            ),
          );
        }
      }
    }

    return null;
  }

  SudokuSolveStep _candidateRemovalStep(
    String ruleId,
    int? value,
    Map<CellId, Set<int>> removals,
    Map<CellId, Set<int>> candidates,
    List<CellId> witnesses, {
    Map<String, Object?> arguments = const {},
  }) => SudokuSolveStep(
    ruleId: ruleId,
    highlights: [
      ...witnesses.map(CellTarget.new),
      ...removals.keys.map(CellTarget.new),
    ],
    actions: [
      for (final entry in removals.entries)
        SetSudokuNotes(
          entry.key,
          candidates[entry.key]!..removeAll(entry.value),
        ),
    ],
    arguments: {
      ...arguments,
      'value': value,
      'removed': removals.values.fold<int>(0, (n, v) => n + v.length),
      'evidence': _cellsData(witnesses),
      'changes': _cellsData(removals.keys),
    },
  );

  Set<CellId> _filledPeers(
    SudokuPuzzle puzzle,
    Map<CellId, int> values,
    CellId cell,
  ) => {
    for (final unit in puzzle.units)
      if (unit.contains(cell))
        for (final peer in unit)
          if (peer != cell && values.containsKey(peer)) peer,
  };

  Map<CellId, Set<int>> _preserveEliminations(
    Map<CellId, Set<int>> current,
    Map<CellId, Set<int>> previous,
  ) => {
    for (final entry in current.entries)
      entry.key: previous[entry.key] == null
          ? entry.value
          : entry.value.intersection(previous[entry.key]!),
  };

  List<List<int>> _cellsData(Iterable<CellId> cells) => [
    for (final cell in cells) [cell.row, cell.column],
  ];

  String _unitName(SudokuPuzzle puzzle, int unitIndex) {
    if (unitIndex < puzzle.size) return '行';
    if (unitIndex < puzzle.size * 2) return '列';
    return '宫';
  }
}

final class _Deduction {
  const _Deduction(this.step);

  final SudokuSolveStep step;
}

final class SudokuGenerator
    implements PuzzleGenerator<GeneratedSudokuPuzzle, SudokuGenerationOptions> {
  const SudokuGenerator();

  @override
  GeneratedSudokuPuzzle generate(SudokuGenerationOptions options) {
    if (options.size != 6 && options.size != 9) {
      throw ArgumentError.value(
        options.size,
        'size',
        'Sudoku supports 6 or 9.',
      );
    }
    if (!options.clueDensity.isFinite ||
        options.clueDensity < 0 ||
        options.clueDensity > 1) {
      throw ArgumentError.value(
        options.clueDensity,
        'clueDensity',
        'Must be 0...1.',
      );
    }
    final random = Random(options.seed);
    final puzzleShell = SudokuPuzzle(size: options.size, givens: const {});
    final cells = puzzleShell.cells;
    final minimumClues = options.size == 6 ? 8 : 17;
    final densityTargetClues = max(
      minimumClues,
      (cells.length * options.clueDensity).round(),
    ).clamp(minimumClues, cells.length);
    // Technique tiers have practical clue-count ranges. Keep density as the
    // target within those ranges; when the two settings conflict, preserving
    // the requested solving techniques is more important than exact density.
    final (minimumRatio, maximumRatio) = switch (options.difficulty) {
      SudokuDifficulty.easy => options.size == 9 ? (.58, .86) : (.66, .88),
      SudokuDifficulty.medium => options.size == 9 ? (.28, .35) : (.28, .40),
      SudokuDifficulty.hard => options.size == 9 ? (.19, .38) : (.18, .30),
    };
    final targetClues = densityTargetClues
        .clamp(
          max(minimumClues, (cells.length * minimumRatio).round()),
          max(minimumClues, (cells.length * maximumRatio).round()),
        )
        .toInt();
    GeneratedSudokuPuzzle? best;
    var bestScore = double.infinity;
    final attempts = options.difficulty == SudokuDifficulty.easy ? 12 : 64;
    for (var attempt = 0; attempt < attempts; attempt++) {
      final solutionValues = _randomSolution(puzzleShell, random);
      final clues = Map<CellId, int>.from(solutionValues);
      final order = cells.toList()..shuffle(random);
      for (final cell in order) {
        if (clues.length <= targetClues) break;
        final value = clues.remove(cell);
        final candidate = SudokuPuzzle(size: options.size, givens: clues);
        if (const SudokuSolver().countSolutions(candidate) != 1) {
          clues[cell] = value!;
        }
      }
      final puzzle = SudokuPuzzle(size: options.size, givens: clues);
      final solveResult = const SudokuSolver().solve(puzzle);
      final achievedDifficulty = _difficultyFor(solveResult);
      // Difficulty is the user's primary choice. Treat clue density as a
      // soft target, but never let a closer clue count outweigh a matching
      // solving-technique tier.
      final distance =
          (achievedDifficulty == options.difficulty ? 0 : 2) +
          (clues.length - targetClues).abs() / cells.length;
      final generated = GeneratedSudokuPuzzle(
        puzzle: puzzle,
        solution: SudokuState(values: solutionValues),
        solveResult: solveResult,
      );
      if (distance < bestScore) {
        best = generated;
        bestScore = distance;
      }
      if (achievedDifficulty == options.difficulty &&
          clues.length <= targetClues + 2) {
        return generated;
      }
    }
    if (options.size == 6 &&
        options.difficulty == SudokuDifficulty.hard &&
        (best == null ||
            _difficultyFor(best.solveResult) != SudokuDifficulty.hard)) {
      return _hardSixBySix(random);
    }
    if (best != null) return best;
    throw StateError('Unable to generate a unique Sudoku puzzle.');
  }

  GeneratedSudokuPuzzle _hardSixBySix(Random random) {
    const rawGivens = [
      [3, 5, 4],
      [2, 3, 5],
      [5, 5, 5],
      [1, 4, 2],
      [0, 2, 3],
      [5, 4, 4],
      [0, 3, 4],
      [1, 1, 5],
      [3, 4, 3],
      [3, 2, 1],
      [5, 0, 6],
      [4, 0, 3],
      [4, 2, 5],
      [3, 0, 5],
    ];
    final rowBands = [0, 1, 2]..shuffle(random);
    final rows = <int>[];
    for (final band in rowBands) {
      final members = [band * 2, band * 2 + 1]..shuffle(random);
      rows.addAll(members);
    }
    final columnStacks = [0, 1]..shuffle(random);
    final columns = <int>[];
    for (final stack in columnStacks) {
      final members = [stack * 3, stack * 3 + 1, stack * 3 + 2]
        ..shuffle(random);
      columns.addAll(members);
    }
    final digits = [1, 2, 3, 4, 5, 6]..shuffle(random);
    final rowMap = {for (var index = 0; index < 6; index++) rows[index]: index};
    final columnMap = {
      for (var index = 0; index < 6; index++) columns[index]: index,
    };
    final digitMap = {
      for (var index = 0; index < 6; index++) index + 1: digits[index],
    };
    final givens = <CellId, int>{
      for (final clue in rawGivens)
        CellId(rowMap[clue[0]]!, columnMap[clue[1]]!): digitMap[clue[2]]!,
    };
    final puzzle = SudokuPuzzle(size: 6, givens: givens);
    final solveResult = const SudokuSolver().solve(puzzle);
    final solution = const SudokuSolver()._firstSolution(puzzle, givens);
    if (solution == null ||
        _difficultyFor(solveResult) != SudokuDifficulty.hard) {
      throw StateError('Unable to construct a hard 6x6 Sudoku puzzle.');
    }
    return GeneratedSudokuPuzzle(
      puzzle: puzzle,
      solution: SudokuState(values: solution),
      solveResult: solveResult,
    );
  }

  Map<CellId, int> _randomSolution(SudokuPuzzle puzzle, Random random) {
    final values = <CellId, int>{};
    bool fill() {
      final solver = const SudokuSolver();
      final candidates = solver.candidatesFor(puzzle, values);
      if (values.length == puzzle.size * puzzle.size) return true;
      final cell = solver.mostConstrainedCell(puzzle, values, candidates);
      if (cell == null) return false;
      final options = candidates[cell]!.toList()..shuffle(random);
      for (final value in options) {
        values[cell] = value;
        if (fill()) return true;
        values.remove(cell);
      }
      return false;
    }

    if (!fill()) throw StateError('Unable to create a completed Sudoku grid.');
    return values;
  }

  SudokuDifficulty _difficultyFor(SudokuSolveResult result) {
    if (result.steps.any(
      (step) =>
          step.ruleId == 'sudoku.contradictionSearch' ||
          step.ruleId == 'sudoku.contradictionElimination' ||
          step.ruleId == 'sudoku.boxLine',
    )) {
      return SudokuDifficulty.hard;
    }
    if (result.steps.any((step) => step.ruleId == 'sudoku.pair')) {
      return SudokuDifficulty.medium;
    }
    return SudokuDifficulty.easy;
  }
}
