import 'dart:math';

import '../../generation/puzzle_generator.dart';
import '../../interaction/puzzle_action.dart';
import '../../solver/solve_step.dart';
import '../../topology/grid_topology.dart';
import 'slitherlink.dart';

/// The solved state and a proof-like sequence of actions that reaches it.
final class SlitherlinkSolveResult {
  const SlitherlinkSolveResult({
    required this.state,
    required this.steps,
    required this.solutionCount,
  });

  final SlitherlinkState state;
  final List<SolveStep<SlitherlinkAction>> steps;
  final int solutionCount;

  bool get hasUniqueSolution => solutionCount == 1;
}

/// A generated puzzle includes the answer only for validation and test use.
/// The UI should expose [puzzle], never [solution].
final class GeneratedSlitherlinkPuzzle {
  const GeneratedSlitherlinkPuzzle({
    required this.puzzle,
    required this.solution,
    required this.solveResult,
  });

  final SlitherlinkPuzzle puzzle;
  final SlitherlinkState solution;
  final SlitherlinkSolveResult solveResult;
}

enum PuzzleDifficulty { easy, normal, hard }

/// Generation controls owned by Slitherlink.
///
/// [includeBlankCells] controls whether some cells may omit a clue entirely.
/// [seed] is optional and makes a generated puzzle reproducible when given.
final class SlitherlinkGenerationOptions implements PuzzleGenerationOptions {
  const SlitherlinkGenerationOptions({
    required this.rows,
    required this.columns,
    this.difficulty = PuzzleDifficulty.normal,
    this.includeBlankCells = true,
    this.seed,
  });

  final int rows;
  final int columns;
  final PuzzleDifficulty difficulty;
  final bool includeBlankCells;
  final int? seed;
}

/// Generates sparse, irregular Slitherlink puzzles from a random polyomino.
///
/// Each candidate starts as a single loop around a connected group of cells.
/// Clues are then removed one at a time, but only when the puzzle remains
/// uniquely solvable.
final class SlitherlinkGenerator
    implements
        PuzzleGenerator<
          GeneratedSlitherlinkPuzzle,
          SlitherlinkGenerationOptions
        > {
  const SlitherlinkGenerator();

  @override
  GeneratedSlitherlinkPuzzle generate(SlitherlinkGenerationOptions options) {
    if (options.rows < 1 || options.columns < 1) {
      throw ArgumentError('A generated puzzle needs at least one cell.');
    }
    final random = Random(options.seed);
    final solver = const SlitherlinkSolver();
    final attemptLimit = switch (options.difficulty) {
      PuzzleDifficulty.easy => 1,
      PuzzleDifficulty.normal => 4,
      PuzzleDifficulty.hard => 8,
    };
    GeneratedSlitherlinkPuzzle? bestCandidate;
    var bestDifficultyDistance = double.infinity;
    for (var attempt = 0; attempt < attemptLimit; attempt++) {
      final topology = GridTopology(
        rows: options.rows,
        columns: options.columns,
      );
      final cells = _randomLoopCells(topology, random, options.difficulty);
      final hasRoomForIrregularShape = options.rows > 1 && options.columns > 1;
      if (hasRoomForIrregularShape &&
          attempt < attemptLimit - 1 &&
          _isRectangle(cells)) {
        continue;
      }
      final solution = _loopAroundCells(topology: topology, cells: cells);
      final fullClues = <CellId, int>{
        for (var row = 0; row < options.rows; row++)
          for (var column = 0; column < options.columns; column++)
            CellId(row, column): topology
                .edgesAround(CellId(row, column))
                .where(
                  (edge) => solution.stateOf(edge) == SlitherlinkEdgeState.line,
                )
                .length,
      };
      final fullPuzzle = SlitherlinkPuzzle(
        topology: topology,
        clues: fullClues,
      );
      if (fullPuzzle.check(solution).status != CheckStatus.solved) continue;
      final fullResult = solver.solve(fullPuzzle);
      if (!fullResult.hasUniqueSolution) continue;
      final clues = options.includeBlankCells
          ? _removeRedundantClues(
              topology: topology,
              fullClues: fullClues,
              random: random,
              solver: solver,
              minimumClueCount: _minimumClueCount(
                options,
                fullClueCount: fullClues.length,
                rows: options.rows,
                columns: options.columns,
              ),
            ) ??
              fullClues
          : fullClues;
      final puzzle = SlitherlinkPuzzle(topology: topology, clues: clues);
      final result = clues.length == fullClues.length
          ? fullResult
          : solver.solve(puzzle);
      if (result.hasUniqueSolution) {
        final candidate = GeneratedSlitherlinkPuzzle(
          puzzle: puzzle,
          solution: solution,
          solveResult: result,
        );
        final difficultyDistance = _difficultyDistance(candidate, options);
        if (difficultyDistance < bestDifficultyDistance) {
          bestCandidate = candidate;
          bestDifficultyDistance = difficultyDistance;
        }
        if (difficultyDistance < .2) return candidate;
      }
    }
    if (bestCandidate != null) return bestCandidate;
    throw StateError(
      'Could not generate a unique irregular Slitherlink puzzle.',
    );
  }

  Set<CellId> _randomLoopCells(
    GridTopology topology,
    Random random,
    PuzzleDifficulty difficulty,
  ) {
    final cells = <CellId>{
      CellId(random.nextInt(topology.rows), random.nextInt(topology.columns)),
    };
    final area = topology.rows * topology.columns;
    final maximumSize = min(area, area.clamp(8, 15));
    final range = switch (difficulty) {
      PuzzleDifficulty.easy => (4, (maximumSize * .55).round()),
      PuzzleDifficulty.normal => (7, (maximumSize * .75).round()),
      PuzzleDifficulty.hard => (9, maximumSize),
    };
    final lowerBound = range.$1.clamp(1, maximumSize);
    final upperBound = range.$2.clamp(lowerBound, maximumSize);
    final targetSize = lowerBound + random.nextInt(upperBound - lowerBound + 1);
    while (cells.length < targetSize) {
      final candidates = <CellId>{
        for (final cell in cells) ..._neighbours(topology, cell),
      }..removeAll(cells);
      if (candidates.isEmpty) break;
      cells.add(candidates.elementAt(random.nextInt(candidates.length)));
    }
    return cells;
  }

  Iterable<CellId> _neighbours(GridTopology topology, CellId cell) sync* {
    const offsets = [(-1, 0), (1, 0), (0, -1), (0, 1)];
    for (final offset in offsets) {
      final neighbour = CellId(cell.row + offset.$1, cell.column + offset.$2);
      if (topology.containsCell(neighbour)) yield neighbour;
    }
  }

  bool _isRectangle(Set<CellId> cells) {
    final rows = cells.map((cell) => cell.row);
    final columns = cells.map((cell) => cell.column);
    final height =
        rows.reduce((a, b) => a > b ? a : b) -
        rows.reduce((a, b) => a < b ? a : b) +
        1;
    final width =
        columns.reduce((a, b) => a > b ? a : b) -
        columns.reduce((a, b) => a < b ? a : b) +
        1;
    return cells.length == height * width;
  }

  SlitherlinkState _loopAroundCells({
    required GridTopology topology,
    required Set<CellId> cells,
  }) {
    return SlitherlinkState({
      for (final edge in topology.allEdges)
        edge: topology.cellsBeside(edge).where(cells.contains).length == 1
            ? SlitherlinkEdgeState.line
            : SlitherlinkEdgeState.crossed,
    });
  }

  Map<CellId, int>? _removeRedundantClues({
    required GridTopology topology,
    required Map<CellId, int> fullClues,
    required Random random,
    required SlitherlinkSolver solver,
    required int minimumClueCount,
  }) {
    final clues = Map<CellId, int>.from(fullClues);
    final order = fullClues.keys.toList()..shuffle(random);
    for (final cell in order) {
      if (clues.length <= minimumClueCount) break;
      final clue = clues.remove(cell);
      if (clue == null) continue;
      final candidate = SlitherlinkPuzzle(topology: topology, clues: clues);
      try {
        if (!solver.solve(candidate).hasUniqueSolution) {
          clues[cell] = clue;
        }
      } on StateError {
        clues[cell] = clue;
      }
    }
    return clues.length < fullClues.length ? clues : null;
  }

  int _minimumClueCount(
    SlitherlinkGenerationOptions options, {
    required int fullClueCount,
    required int rows,
    required int columns,
  }) {
    if (fullClueCount <= 1) return fullClueCount;
    final preferred = switch (options.difficulty) {
      PuzzleDifficulty.easy => (fullClueCount * .68).ceil(),
      PuzzleDifficulty.normal => (fullClueCount * .42).ceil(),
      PuzzleDifficulty.hard => (fullClueCount * .25).ceil(),
    };
    final area = rows * columns;
    final scaleFloor = switch (options.difficulty) {
      PuzzleDifficulty.easy => (area * .28).ceil(),
      PuzzleDifficulty.normal => (area * .20).ceil(),
      PuzzleDifficulty.hard => (area * .13).ceil(),
    };
    return max(1, max(preferred, scaleFloor)).clamp(1, fullClueCount - 1);
  }

  double _difficultyDistance(
    GeneratedSlitherlinkPuzzle candidate,
    SlitherlinkGenerationOptions options,
  ) {
    final topology = candidate.puzzle.topology;
    final clueRatio =
        candidate.puzzle.clues.length / (topology.rows * topology.columns);
    final searchSteps = candidate.solveResult.steps
        .where((step) => step.ruleId == 'slitherlink.assumptionContradiction')
        .length;
    final targetClueRatio = switch (options.difficulty) {
      PuzzleDifficulty.easy => .68,
      PuzzleDifficulty.normal => .47,
      PuzzleDifficulty.hard => .32,
    };
    final targetSearchSteps = switch (options.difficulty) {
      PuzzleDifficulty.easy => 0,
      PuzzleDifficulty.normal => 2,
      PuzzleDifficulty.hard => 5,
    };
    final expectedSteps = candidate.puzzle.topology.allEdges.length * .45;
    final stepRatio = candidate.solveResult.steps.length / expectedSteps;
    final targetStepRatio = switch (options.difficulty) {
      PuzzleDifficulty.easy => .65,
      PuzzleDifficulty.normal => 1.15,
      PuzzleDifficulty.hard => 1.8,
    };
    final minimumSearchSteps = switch (options.difficulty) {
      PuzzleDifficulty.easy => 0,
      PuzzleDifficulty.normal => 1,
      PuzzleDifficulty.hard => 3,
    };
    final searchPenalty = searchSteps < minimumSearchSteps
        ? (minimumSearchSteps - searchSteps) * 2.0
        : (searchSteps - targetSearchSteps).abs() * .22;
    return (clueRatio - targetClueRatio).abs() * 2 +
        searchPenalty +
        (stepRatio - targetStepRatio).abs() * .35;
  }
}

/// Complete finite solver for the current grid-based Slitherlink model.
/// It exhausts constraint branches only after explainable local deductions.
final class SlitherlinkSolver {
  const SlitherlinkSolver({this.maxSearchNodes = 200000});

  final int maxSearchNodes;

  SlitherlinkSolveResult solve(
    SlitherlinkPuzzle puzzle, {
    SlitherlinkState? initialState,
  }) {
    var state = initialState ?? puzzle.initialState;
    final steps = <SolveStep<SlitherlinkAction>>[];

    while (true) {
      final propagation = _propagate(puzzle, state);
      if (propagation == null) {
        throw StateError('The supplied Slitherlink state is contradictory.');
      }
      state = propagation.state;
      steps.addAll(propagation.steps);
      if (_isComplete(puzzle, state)) {
        final solutions = _countSolutions(
          puzzle,
          state,
          _SearchBudget(maxSearchNodes),
          2,
        );
        return SlitherlinkSolveResult(
          state: state,
          steps: steps,
          solutionCount: solutions,
        );
      }

      final edge = _nextUndecidedEdge(puzzle, state);
      if (edge == null) {
        throw StateError(
          'No undecided edge exists, but the puzzle is not complete.',
        );
      }
      final lineCount = _countSolutions(
        puzzle,
        state.withEdge(edge, SlitherlinkEdgeState.line),
        _SearchBudget(maxSearchNodes),
        2,
      );
      final crossCount = _countSolutions(
        puzzle,
        state.withEdge(edge, SlitherlinkEdgeState.crossed),
        _SearchBudget(maxSearchNodes),
        2,
      );
      if (lineCount == 0 && crossCount == 0) {
        throw StateError(
          'No valid completion exists for this Slitherlink puzzle.',
        );
      }
      if (lineCount > 0 && crossCount > 0) {
        return SlitherlinkSolveResult(
          state: state,
          steps: steps,
          solutionCount: 2,
        );
      }
      final forcedState = lineCount > 0
          ? SlitherlinkEdgeState.line
          : SlitherlinkEdgeState.crossed;
      final rejectedState = forcedState == SlitherlinkEdgeState.line
          ? SlitherlinkEdgeState.crossed
          : SlitherlinkEdgeState.line;
      state = state.withEdge(edge, forcedState);
      steps.add(
        SolveStep(
          ruleId: 'slitherlink.assumptionContradiction',
          highlights: [EdgeTarget(edge)],
          actions: [SetSlitherlinkEdge(edge, forcedState)],
          arguments: {
            'assumed': rejectedState.name,
            'result': forcedState.name,
          },
        ),
      );
    }
  }

  _Propagation? _propagate(SlitherlinkPuzzle puzzle, SlitherlinkState input) {
    var state = input;
    final steps = <SolveStep<SlitherlinkAction>>[];
    while (true) {
      final deductions = <_Deduction>[];
      for (final entry in puzzle.clues.entries) {
        final edges = puzzle.topology.edgesAround(entry.key);
        final lines = edges
            .where((edge) => state.stateOf(edge) == SlitherlinkEdgeState.line)
            .length;
        final empty = edges
            .where((edge) => state.stateOf(edge) == SlitherlinkEdgeState.empty)
            .toList();
        if (lines > entry.value || lines + empty.length < entry.value) {
          return null;
        }
        if (empty.isNotEmpty && lines == entry.value) {
          deductions.add(
            _Deduction(
              ruleId: 'slitherlink.clueReached',
              highlights: [CellTarget(entry.key), ...empty.map(EdgeTarget.new)],
              actions: [
                for (final edge in empty)
                  SetSlitherlinkEdge(edge, SlitherlinkEdgeState.crossed),
              ],
              arguments: {'clue': entry.value, 'lines': lines},
            ),
          );
        }
        if (empty.isNotEmpty && lines + empty.length == entry.value) {
          deductions.add(
            _Deduction(
              ruleId: 'slitherlink.remainingEdgesRequired',
              highlights: [CellTarget(entry.key), ...empty.map(EdgeTarget.new)],
              actions: [
                for (final edge in empty)
                  SetSlitherlinkEdge(edge, SlitherlinkEdgeState.line),
              ],
              arguments: {'clue': entry.value, 'lines': lines},
            ),
          );
        }
      }
      for (var row = 0; row <= puzzle.topology.rows; row++) {
        for (var column = 0; column <= puzzle.topology.columns; column++) {
          final vertex = VertexId(row, column);
          final edges = puzzle.topology.edgesAt(vertex);
          final lines = edges
              .where((edge) => state.stateOf(edge) == SlitherlinkEdgeState.line)
              .length;
          final empty = edges
              .where(
                (edge) => state.stateOf(edge) == SlitherlinkEdgeState.empty,
              )
              .toList();
          if (lines > 2 || (lines == 1 && empty.isEmpty)) {
            return null;
          }
          if (empty.isEmpty) continue;
          if (lines == 2 || (lines == 0 && empty.length == 1)) {
            deductions.add(
              _Deduction(
                ruleId: 'slitherlink.vertexDegree',
                highlights: [
                  VertexTarget(vertex),
                  ...empty.map(EdgeTarget.new),
                ],
                actions: [
                  for (final edge in empty)
                    SetSlitherlinkEdge(edge, SlitherlinkEdgeState.crossed),
                ],
                arguments: {'lines': lines},
              ),
            );
          } else if (lines == 1 && empty.length == 1) {
            deductions.add(
              _Deduction(
                ruleId: 'slitherlink.preventOpenEnd',
                highlights: [
                  VertexTarget(vertex),
                  ...empty.map(EdgeTarget.new),
                ],
                actions: [
                  for (final edge in empty)
                    SetSlitherlinkEdge(edge, SlitherlinkEdgeState.line),
                ],
                arguments: const {},
              ),
            );
          }
        }
      }
      final applicable = _mergeDeductions(deductions, state);
      if (applicable == null) return null;
      if (applicable.isEmpty) return _Propagation(state: state, steps: steps);
      final deduction = applicable.first;
      for (final action in deduction.actions) {
        state = state.withEdge(action.edge, action.state);
      }
      steps.add(
        SolveStep(
          ruleId: deduction.ruleId,
          highlights: deduction.highlights,
          actions: deduction.actions,
          arguments: deduction.arguments,
        ),
      );
    }
  }

  List<_Deduction>? _mergeDeductions(
    List<_Deduction> deductions,
    SlitherlinkState state,
  ) {
    final assignments = <EdgeId, SlitherlinkEdgeState>{};
    final applicable = <_Deduction>[];
    for (final deduction in deductions) {
      var hasChange = false;
      for (final action in deduction.actions) {
        final existing = assignments[action.edge];
        if (existing != null && existing != action.state) return null;
        if (state.stateOf(action.edge) != action.state) {
          assignments[action.edge] = action.state;
          hasChange = true;
        }
      }
      if (hasChange) applicable.add(deduction);
    }
    return applicable;
  }

  int _countSolutions(
    SlitherlinkPuzzle puzzle,
    SlitherlinkState input,
    _SearchBudget budget,
    int limit,
  ) {
    if (--budget.remaining < 0) {
      throw StateError('Solver search budget exceeded.');
    }
    final propagation = _propagate(puzzle, input);
    if (propagation == null) return 0;
    final state = propagation.state;
    if (_isComplete(puzzle, state)) return 1;
    final edge = _nextUndecidedEdge(puzzle, state);
    if (edge == null) return 0;
    final lineCount = _countSolutions(
      puzzle,
      state.withEdge(edge, SlitherlinkEdgeState.line),
      budget,
      limit,
    );
    if (lineCount >= limit) return limit;
    final crossCount = _countSolutions(
      puzzle,
      state.withEdge(edge, SlitherlinkEdgeState.crossed),
      budget,
      limit - lineCount,
    );
    return lineCount + crossCount;
  }

  bool _isComplete(SlitherlinkPuzzle puzzle, SlitherlinkState state) {
    if (puzzle.topology.allEdges.any(
      (edge) => state.stateOf(edge) == SlitherlinkEdgeState.empty,
    )) {
      return false;
    }
    return puzzle.check(state).status == CheckStatus.solved;
  }

  EdgeId? _nextUndecidedEdge(SlitherlinkPuzzle puzzle, SlitherlinkState state) {
    for (final edge in puzzle.topology.allEdges) {
      if (state.stateOf(edge) == SlitherlinkEdgeState.empty) return edge;
    }
    return null;
  }
}

final class _Propagation {
  const _Propagation({required this.state, required this.steps});

  final SlitherlinkState state;
  final List<SolveStep<SlitherlinkAction>> steps;
}

final class _Deduction {
  const _Deduction({
    required this.ruleId,
    required this.highlights,
    required this.actions,
    required this.arguments,
  });

  final String ruleId;
  final List<PuzzleTarget> highlights;
  final List<SetSlitherlinkEdge> actions;
  final Map<String, Object?> arguments;
}

final class _SearchBudget {
  _SearchBudget(this.remaining);

  int remaining;
}
