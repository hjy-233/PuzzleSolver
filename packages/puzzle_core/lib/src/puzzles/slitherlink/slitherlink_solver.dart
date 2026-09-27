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
/// [clueDensity] adjusts density around each difficulty's default; 0.5 keeps
/// the default, while higher values retain more clues.
/// [seed] is optional and makes a generated puzzle reproducible when given.
final class SlitherlinkGenerationOptions implements PuzzleGenerationOptions {
  const SlitherlinkGenerationOptions({
    required this.rows,
    required this.columns,
    this.difficulty = PuzzleDifficulty.normal,
    this.includeBlankCells = true,
    this.clueDensity = 0.55,
    this.includeSolveSteps = true,
    this.seed,
  });

  final int rows;
  final int columns;
  final PuzzleDifficulty difficulty;
  final bool includeBlankCells;

  /// Density adjustment from 0.0 (sparser) to 1.0 (denser).
  final double clueDensity;
  final bool includeSolveSteps;
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
    if (!options.clueDensity.isFinite ||
        options.clueDensity < 0 ||
        options.clueDensity > 1) {
      throw ArgumentError.value(
        options.clueDensity,
        'clueDensity',
        'Must be between 0.0 and 1.0.',
      );
    }
    final random = Random(options.seed);
    final solver = const SlitherlinkSolver();
    final area = options.rows * options.columns;
    final quickGeneration = !options.includeSolveSteps;
    final uniquenessSolver = SlitherlinkSolver(
      maxSearchNodes: quickGeneration
          ? area >= 64
                ? 2000
                : area >= 36
                ? 8000
                : 10000
          : area >= 64
          ? 2000
          : area >= 36
          ? 8000
          : 200000,
    );
    final attemptLimit = quickGeneration
        ? switch ((area >= 64, options.difficulty)) {
            (true, PuzzleDifficulty.easy) => 4,
            (true, PuzzleDifficulty.normal) => 6,
            (true, PuzzleDifficulty.hard) => 8,
            (false, PuzzleDifficulty.easy) => 2,
            (false, PuzzleDifficulty.normal) => 10,
            (false, PuzzleDifficulty.hard) => 16,
          }
        : switch (options.difficulty) {
            PuzzleDifficulty.easy => 1,
            PuzzleDifficulty.normal => 8,
            PuzzleDifficulty.hard => 16,
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
          !_isIrregularEnough(topology, cells)) {
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
      late final SlitherlinkSolveResult fullResult;
      if (options.includeSolveSteps) {
        fullResult = solver.solve(fullPuzzle);
        if (!fullResult.hasUniqueSolution) continue;
      } else {
        try {
          if (uniquenessSolver.countSolutions(fullPuzzle) != 1) continue;
        } on StateError {
          continue;
        }
        fullResult = _knownSolutionResult(solution);
      }
      final clues = options.includeBlankCells
          ? _removeRedundantClues(
                  topology: topology,
                  fullClues: fullClues,
                  random: random,
                  solver: uniquenessSolver,
                  maximumChecks: quickGeneration
                      ? switch ((area >= 64, options.difficulty)) {
                          (true, PuzzleDifficulty.easy) => 8,
                          (true, PuzzleDifficulty.normal) => 32,
                          (true, PuzzleDifficulty.hard) => 24,
                          (false, PuzzleDifficulty.easy) => 12,
                          (false, PuzzleDifficulty.normal) => 36,
                          (false, PuzzleDifficulty.hard) => 60,
                        }
                      : null,
                  minimumClueCount: _minimumClueCount(
                    options,
                    fullClueCount: fullClues.length,
                    rows: options.rows,
                    columns: options.columns,
                  ),
                  loopCells: cells,
                  minimumLoopClueCount: _minimumLoopClueCount(
                    options.difficulty,
                    cells.length,
                  ),
                  boundaryCells: {
                    for (final cell in cells)
                      if (fullClues[cell]! > 0) cell,
                  },
                  minimumBoundaryClueCount: _minimumBoundaryClueCount(
                    options.difficulty,
                    cells.where((cell) => fullClues[cell]! > 0).length,
                  ),
                ) ??
                fullClues
          : fullClues;
      final puzzle = SlitherlinkPuzzle(topology: topology, clues: clues);
      final result = clues.length == fullClues.length
          ? fullResult
          : options.includeSolveSteps
          ? solver.solve(puzzle)
          : _knownSolutionResult(solution);
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
        if (quickGeneration || difficultyDistance < .2) return candidate;
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
    final maximumSize = min(
      area,
      area < 36 ? area.clamp(8, 15).toInt() : max(15, (area * .68).round()),
    );
    final range = switch (difficulty) {
      PuzzleDifficulty.easy => (
        max(4, (maximumSize * .25).round()),
        (maximumSize * .55).round(),
      ),
      PuzzleDifficulty.normal => (
        (maximumSize * .55).round(),
        (maximumSize * .8).round(),
      ),
      PuzzleDifficulty.hard => ((maximumSize * .75).round(), maximumSize),
    };
    final lowerBound = range.$1.clamp(1, maximumSize);
    final upperBound = range.$2.clamp(lowerBound, maximumSize);
    final targetSize = lowerBound + random.nextInt(upperBound - lowerBound + 1);
    while (cells.length < targetSize) {
      final candidates = <CellId>{
        for (final cell in cells) ..._neighbours(topology, cell),
      }..removeAll(cells);
      if (candidates.isEmpty) break;
      final weightedCandidates = [
        for (final candidate in candidates)
          for (
            var weight = 0;
            weight < _growthWeight(topology, cells, candidate);
            weight++
          )
            candidate,
      ];
      cells.add(weightedCandidates[random.nextInt(weightedCandidates.length)]);
    }
    return cells;
  }

  int _growthWeight(
    GridTopology topology,
    Set<CellId> cells,
    CellId candidate,
  ) {
    final neighbours = _neighbours(
      topology,
      candidate,
    ).where(cells.contains).length;
    return switch (neighbours) {
      1 => 4,
      2 => 3,
      3 => 2,
      _ => 1,
    };
  }

  Iterable<CellId> _neighbours(GridTopology topology, CellId cell) sync* {
    const offsets = [(-1, 0), (1, 0), (0, -1), (0, 1)];
    for (final offset in offsets) {
      final neighbour = CellId(cell.row + offset.$1, cell.column + offset.$2);
      if (topology.containsCell(neighbour)) yield neighbour;
    }
  }

  bool _isIrregularEnough(GridTopology topology, Set<CellId> cells) {
    final boundary = topology.allEdges
        .where(
          (edge) =>
              topology.cellsBeside(edge).where(cells.contains).length == 1,
        )
        .toSet();
    var turns = 0;
    for (var row = 0; row <= topology.rows; row++) {
      for (var column = 0; column <= topology.columns; column++) {
        final incident = topology
            .edgesAt(VertexId(row, column))
            .where(boundary.contains)
            .toList();
        if (incident.length == 2 &&
            incident[0].orientation != incident[1].orientation) {
          turns++;
        }
      }
    }
    return turns >= max(6, (boundary.length * .28).ceil());
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
    required int? maximumChecks,
    required int minimumClueCount,
    required Set<CellId> loopCells,
    required int minimumLoopClueCount,
    required Set<CellId> boundaryCells,
    required int minimumBoundaryClueCount,
  }) {
    final clues = Map<CellId, int>.from(fullClues);
    final order = fullClues.keys.toList()..shuffle(random);
    order.sort((left, right) {
      final leftEasy = fullClues[left] == 0 || fullClues[left] == 3;
      final rightEasy = fullClues[right] == 0 || fullClues[right] == 3;
      return (rightEasy ? 1 : 0).compareTo(leftEasy ? 1 : 0);
    });
    var cursor = 0;
    var batchSize = max(1, ((clues.length - minimumClueCount) / 12).ceil());
    final checkLimit =
        maximumChecks ??
        (topology.rows * topology.columns >= 64 ? 16 : order.length * 2);
    var checks = 0;
    while (cursor < order.length && clues.length > minimumClueCount) {
      if (checks >= checkLimit) break;
      final batch = order
          .skip(cursor)
          .where(clues.containsKey)
          .take(min(batchSize, clues.length - minimumClueCount))
          .toList();
      if (batch.isEmpty) break;
      final removed = <CellId, int>{
        for (final cell in batch) cell: clues.remove(cell)!,
      };
      final loopClues = clues.keys.where(loopCells.contains).length;
      final boundaryClues = clues.keys.where(boundaryCells.contains).length;
      if (loopClues < minimumLoopClueCount ||
          boundaryClues < minimumBoundaryClueCount) {
        clues.addAll(removed);
        if (batchSize > 1) {
          batchSize = max(1, batchSize ~/ 2);
        } else {
          cursor += batch.length;
        }
        continue;
      }
      final candidate = SlitherlinkPuzzle(topology: topology, clues: clues);
      checks++;
      try {
        if (solver.countSolutions(candidate) == 1) {
          cursor += batch.length;
          continue;
        }
      } on StateError {
        // Keep the known-unique clues when proving a sparser set is costly.
      }
      clues.addAll(removed);
      if (batchSize > 1) {
        batchSize = max(1, batchSize ~/ 2);
      } else {
        cursor += batch.length;
      }
    }
    return clues.length < fullClues.length ? clues : null;
  }

  SlitherlinkSolveResult _knownSolutionResult(SlitherlinkState solution) =>
      SlitherlinkSolveResult(
        state: solution,
        steps: const [],
        solutionCount: 1,
      );

  int _minimumClueCount(
    SlitherlinkGenerationOptions options, {
    required int fullClueCount,
    required int rows,
    required int columns,
  }) {
    if (fullClueCount <= 1) return fullClueCount;
    final area = rows * columns;
    final difficultyClueRatio = switch (options.difficulty) {
      PuzzleDifficulty.easy => .68,
      PuzzleDifficulty.normal => .44,
      PuzzleDifficulty.hard => .24,
    };
    final baseFloor = max(
      (fullClueCount * difficultyClueRatio).ceil(),
      (area * difficultyClueRatio / 2).ceil(),
    );
    final adjustBy =
        ((fullClueCount - baseFloor) * (options.clueDensity - .5) * 2).round();
    return max(1, baseFloor + adjustBy).clamp(1, fullClueCount - 1);
  }

  int _minimumLoopClueCount(PuzzleDifficulty difficulty, int loopArea) {
    final ratio = switch (difficulty) {
      PuzzleDifficulty.easy => .52,
      PuzzleDifficulty.normal => .36,
      PuzzleDifficulty.hard => .32,
    };
    return max(1, (loopArea * ratio).ceil());
  }

  int _minimumBoundaryClueCount(PuzzleDifficulty difficulty, int count) {
    final ratio = switch (difficulty) {
      PuzzleDifficulty.easy => .42,
      PuzzleDifficulty.normal => .28,
      PuzzleDifficulty.hard => .26,
    };
    return max(1, (count * ratio).ceil());
  }

  double _difficultyDistance(
    GeneratedSlitherlinkPuzzle candidate,
    SlitherlinkGenerationOptions options,
  ) {
    final topology = candidate.puzzle.topology;
    final clueRatio =
        candidate.puzzle.clues.length / (topology.rows * topology.columns);
    final easyClueRatio =
        candidate.puzzle.clues.values
            .where((clue) => clue == 0 || clue == 3)
            .length /
        candidate.puzzle.clues.length;
    final searchSteps = candidate.solveResult.steps
        .where((step) => step.ruleId == 'slitherlink.assumptionContradiction')
        .length;
    final targetClueRatio = switch (options.difficulty) {
      PuzzleDifficulty.easy => .68,
      PuzzleDifficulty.normal => .47,
      PuzzleDifficulty.hard => .25,
    };
    final targetSearchSteps = switch (options.difficulty) {
      PuzzleDifficulty.easy => 0,
      PuzzleDifficulty.normal => 5,
      PuzzleDifficulty.hard => 12,
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
      PuzzleDifficulty.normal => 2,
      PuzzleDifficulty.hard => 7,
    };
    final searchPenalty = searchSteps < minimumSearchSteps
        ? (minimumSearchSteps - searchSteps) * 2.0
        : (searchSteps - targetSearchSteps).abs() * .22;
    return (clueRatio - targetClueRatio).abs() * 2 +
        searchPenalty +
        (stepRatio - targetStepRatio).abs() * .35 +
        (options.difficulty == PuzzleDifficulty.hard ? easyClueRatio * 20 : 0);
  }
}

/// Complete finite solver for the current grid-based Slitherlink model.
/// It exhausts constraint branches only after explainable local deductions.
final class SlitherlinkSolver {
  const SlitherlinkSolver({this.maxSearchNodes = 200000});

  final int maxSearchNodes;

  /// Counts up to [limit] valid completions without building explanation steps.
  int countSolutions(
    SlitherlinkPuzzle puzzle, {
    SlitherlinkState? initialState,
    int limit = 2,
  }) {
    if (limit < 1) {
      throw ArgumentError.value(limit, 'limit', 'Must be positive.');
    }
    return _countSolutions(
      puzzle,
      initialState ?? puzzle.initialState,
      _SearchBudget(maxSearchNodes),
      limit,
    );
  }

  SlitherlinkSolveResult solve(
    SlitherlinkPuzzle puzzle, {
    SlitherlinkState? initialState,
  }) {
    var state = initialState ?? puzzle.initialState;
    final steps = <SolveStep<SlitherlinkAction>>[];
    EdgeId? focusEdge;

    while (true) {
      final propagation = _propagate(puzzle, state, near: focusEdge);
      if (propagation == null) {
        throw StateError('The supplied Slitherlink state is contradictory.');
      }
      state = propagation.state;
      steps.addAll(propagation.steps);
      if (propagation.steps.isNotEmpty &&
          propagation.steps.last.actions.isNotEmpty) {
        final lastAction = propagation.steps.last.actions.last;
        if (lastAction case SetSlitherlinkEdge(:final edge)) {
          focusEdge = edge;
        }
      }
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

      final edge = _nextUndecidedEdge(puzzle, state, near: focusEdge);
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
      focusEdge = edge;
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

  _Propagation? _propagate(
    SlitherlinkPuzzle puzzle,
    SlitherlinkState input, {
    EdgeId? near,
  }) {
    var state = input;
    final steps = <SolveStep<SlitherlinkAction>>[];
    var focusEdge = near;
    while (true) {
      final deductions = <_Deduction>[];

      final zeroCells = puzzle.clues.entries
          .where((entry) => entry.value == 0)
          .map((entry) => entry.key)
          .toList();
      final zeroEdges = <EdgeId>{};
      for (final cell in zeroCells) {
        for (final edge in puzzle.topology.edgesAround(cell)) {
          if (state.stateOf(edge) == SlitherlinkEdgeState.line) return null;
          if (state.stateOf(edge) == SlitherlinkEdgeState.empty) {
            zeroEdges.add(edge);
          }
        }
      }
      if (zeroEdges.isNotEmpty) {
        deductions.add(
          _Deduction(
            ruleId: 'slitherlink.zeroClues',
            highlights: [
              ...zeroCells.map(CellTarget.new),
              ...zeroEdges.map(EdgeTarget.new),
            ],
            actions: [
              for (final edge in zeroEdges)
                SetSlitherlinkEdge(edge, SlitherlinkEdgeState.crossed),
            ],
            arguments: {'cells': zeroCells.length},
          ),
        );
      }

      for (final entry in puzzle.clues.entries) {
        if (entry.value == 0) continue;
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

      final loopClosure = _closedLoopAssignments(puzzle, state);
      if (loopClosure == null) return null;
      if (loopClosure.isNotEmpty) {
        deductions.add(
          _Deduction(
            ruleId: 'slitherlink.loopClosed',
            highlights: [
              ...loopClosure.keys.map(EdgeTarget.new),
              for (final cell in puzzle.clues.keys) CellTarget(cell),
            ],
            actions: [
              for (final edge in loopClosure.keys)
                SetSlitherlinkEdge(edge, SlitherlinkEdgeState.crossed),
            ],
            arguments: {'crosses': loopClosure.length},
          ),
        );
      }

      final insideOutside = _insideOutsideAssignments(puzzle, state);
      if (insideOutside == null) return null;
      if (insideOutside.isNotEmpty) {
        final affectedCells = <CellId>{};
        for (final edge in insideOutside.keys) {
          affectedCells.addAll(puzzle.topology.cellsBeside(edge));
        }
        deductions.add(
          _Deduction(
            ruleId: 'slitherlink.insideOutside',
            highlights: [
              ...affectedCells.map(CellTarget.new),
              ...insideOutside.keys.map(EdgeTarget.new),
            ],
            actions: [
              for (final entry in insideOutside.entries)
                SetSlitherlinkEdge(entry.key, entry.value),
            ],
            arguments: {
              'lines': insideOutside.values
                  .where((value) => value == SlitherlinkEdgeState.line)
                  .length,
            },
          ),
        );
      }

      if (deductions.isEmpty) {
        final windowDeductions = _fourCellWindowDeductions(puzzle, state);
        if (windowDeductions == null) return null;
        deductions.addAll(windowDeductions);
      }

      final applicable = _mergeDeductions(deductions, state);
      if (applicable == null) return null;
      if (applicable.isEmpty) return _Propagation(state: state, steps: steps);
      final deduction = _selectNearbyDeduction(applicable, focusEdge);
      for (final action in deduction.actions) {
        state = state.withEdge(action.edge, action.state);
      }
      if (deduction.actions.isNotEmpty) {
        focusEdge = deduction.actions.last.edge;
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

  _Deduction _selectNearbyDeduction(
    List<_Deduction> deductions,
    EdgeId? focus,
  ) {
    if (focus == null) return deductions.first;
    var selected = deductions.first;
    var selectedDistance = 1 << 30;
    for (final deduction in deductions) {
      var distance = 1 << 30;
      for (final action in deduction.actions) {
        distance = min(distance, _edgeDistance(focus, action.edge));
      }
      if (distance < selectedDistance ||
          (distance == selectedDistance &&
              deduction.actions.length > selected.actions.length)) {
        selected = deduction;
        selectedDistance = distance;
      }
    }
    return selected;
  }

  int _edgeDistance(EdgeId first, EdgeId second) {
    (int, int) center(EdgeId edge) => switch (edge.orientation) {
      EdgeOrientation.horizontal => (edge.row * 2, edge.column * 2 + 1),
      EdgeOrientation.vertical => (edge.row * 2 + 1, edge.column * 2),
    };
    final (firstRow, firstColumn) = center(first);
    final (secondRow, secondColumn) = center(second);
    return (firstRow - secondRow).abs() + (firstColumn - secondColumn).abs();
  }

  Map<EdgeId, SlitherlinkEdgeState>? _insideOutsideAssignments(
    SlitherlinkPuzzle puzzle,
    SlitherlinkState state,
  ) {
    final topology = puzzle.topology;
    final outside = topology.rows * topology.columns;
    final relationships = _ParityUnionFind(outside + 1);
    int cellIndex(CellId cell) => cell.row * topology.columns + cell.column;

    for (final edge in topology.allEdges) {
      final edgeState = state.stateOf(edge);
      if (edgeState == SlitherlinkEdgeState.empty) continue;
      final cells = topology.cellsBeside(edge);
      final first = cellIndex(cells.first);
      final second = cells.length == 2 ? cellIndex(cells.last) : outside;
      final opposite = edgeState == SlitherlinkEdgeState.line;
      if (!relationships.join(first, second, opposite)) return null;
    }

    final assignments = <EdgeId, SlitherlinkEdgeState>{};
    for (final edge in topology.allEdges) {
      if (state.stateOf(edge) != SlitherlinkEdgeState.empty) continue;
      final cells = topology.cellsBeside(edge);
      final first = relationships.find(cellIndex(cells.first));
      final second = relationships.find(
        cells.length == 2 ? cellIndex(cells.last) : outside,
      );
      if (first.$1 != second.$1) continue;
      assignments[edge] = first.$2 == second.$2
          ? SlitherlinkEdgeState.crossed
          : SlitherlinkEdgeState.line;
    }
    return assignments;
  }

  Map<EdgeId, SlitherlinkEdgeState>? _closedLoopAssignments(
    SlitherlinkPuzzle puzzle,
    SlitherlinkState state,
  ) {
    final topology = puzzle.topology;
    final lineEdges = topology.allEdges
        .where((edge) => state.stateOf(edge) == SlitherlinkEdgeState.line)
        .toSet();
    if (lineEdges.isEmpty) return const {};

    final neighbours = <VertexId, Set<VertexId>>{};
    final degree = <VertexId, int>{};
    for (final edge in lineEdges) {
      final vertices = topology.verticesOf(edge);
      neighbours.putIfAbsent(vertices.first, () => {}).add(vertices.last);
      neighbours.putIfAbsent(vertices.last, () => {}).add(vertices.first);
      degree.update(vertices.first, (value) => value + 1, ifAbsent: () => 1);
      degree.update(vertices.last, (value) => value + 1, ifAbsent: () => 1);
    }

    final visited = <VertexId>{};
    Set<VertexId>? closedComponent;
    for (final start in neighbours.keys) {
      if (!visited.add(start)) continue;
      final component = <VertexId>{start};
      final pending = <VertexId>[start];
      while (pending.isNotEmpty) {
        final vertex = pending.removeLast();
        for (final neighbour in neighbours[vertex]!) {
          if (visited.add(neighbour)) {
            component.add(neighbour);
            pending.add(neighbour);
          }
        }
      }
      if (component.every((vertex) => degree[vertex] == 2)) {
        if (closedComponent != null) return null;
        closedComponent = component;
      }
    }
    if (closedComponent == null) return const {};
    if (neighbours.keys.any((vertex) => !closedComponent!.contains(vertex))) {
      return null;
    }

    for (final entry in puzzle.clues.entries) {
      final lines = topology
          .edgesAround(entry.key)
          .where((edge) => state.stateOf(edge) == SlitherlinkEdgeState.line)
          .length;
      if (lines != entry.value) return null;
    }
    return {
      for (final edge in topology.allEdges)
        if (state.stateOf(edge) == SlitherlinkEdgeState.empty)
          edge: SlitherlinkEdgeState.crossed,
    };
  }

  List<_Deduction>? _fourCellWindowDeductions(
    SlitherlinkPuzzle puzzle,
    SlitherlinkState state,
  ) {
    final topology = puzzle.topology;
    if (topology.rows < 2 || topology.columns < 2) return const [];
    final deductions = <_Deduction>[];
    for (var top = 0; top < topology.rows - 1; top++) {
      for (var left = 0; left < topology.columns - 1; left++) {
        final cells = [
          CellId(top, left),
          CellId(top, left + 1),
          CellId(top + 1, left),
          CellId(top + 1, left + 1),
        ];
        final clues = cells.where(puzzle.clues.containsKey).toList();
        final edges = <EdgeId>{
          for (final cell in cells) ...topology.edgesAround(cell),
        };
        final unknown = edges
            .where((edge) => state.stateOf(edge) == SlitherlinkEdgeState.empty)
            .toList();
        final decidedCount = edges.length - unknown.length;
        final hasCornerClue = clues.any(
          (cell) =>
              (cell.row == 0 || cell.row == topology.rows - 1) &&
              (cell.column == 0 || cell.column == topology.columns - 1),
        );
        final constrainedThree = clues.any((cell) => puzzle.clues[cell] == 3);
        final clueTouchesKnownEdge = clues.any(
          (cell) => topology
              .edgesAround(cell)
              .any((edge) => state.stateOf(edge) != SlitherlinkEdgeState.empty),
        );
        if ((clues.length < 2 &&
                decidedCount < 3 &&
                !(hasCornerClue ||
                    (constrainedThree && decidedCount > 0) ||
                    clueTouchesKnownEdge)) ||
            unknown.length > 12) {
          continue;
        }

        final canBeLine = {for (final edge in unknown) edge: false};
        final canBeCrossed = {for (final edge in unknown) edge: false};
        var validCombinations = 0;
        final combinations = 1 << unknown.length;
        for (var mask = 0; mask < combinations; mask++) {
          final candidate = <EdgeId, SlitherlinkEdgeState>{
            for (final edge in edges)
              if (state.stateOf(edge) != SlitherlinkEdgeState.empty)
                edge: state.stateOf(edge),
            for (var index = 0; index < unknown.length; index++)
              unknown[index]: mask & (1 << index) == 0
                  ? SlitherlinkEdgeState.crossed
                  : SlitherlinkEdgeState.line,
          };
          if (!_validFourCellWindow(puzzle, cells, edges, candidate, state)) {
            continue;
          }
          validCombinations++;
          for (final edge in unknown) {
            if (candidate[edge] == SlitherlinkEdgeState.line) {
              canBeLine[edge] = true;
            } else {
              canBeCrossed[edge] = true;
            }
          }
        }
        if (validCombinations == 0) return null;

        final forced = <EdgeId, SlitherlinkEdgeState>{};
        for (final edge in unknown) {
          if (canBeLine[edge] == true && canBeCrossed[edge] == false) {
            forced[edge] = SlitherlinkEdgeState.line;
          } else if (canBeCrossed[edge] == true && canBeLine[edge] == false) {
            forced[edge] = SlitherlinkEdgeState.crossed;
          }
        }
        if (forced.isNotEmpty) {
          deductions.add(
            _Deduction(
              ruleId: 'slitherlink.fourCellWindow',
              highlights: [
                ...cells.map(CellTarget.new),
                ...forced.keys.map(EdgeTarget.new),
              ],
              actions: [
                for (final entry in forced.entries)
                  SetSlitherlinkEdge(entry.key, entry.value),
              ],
              arguments: {'cells': clues.length},
            ),
          );
        }
      }
    }
    return deductions;
  }

  bool _validFourCellWindow(
    SlitherlinkPuzzle puzzle,
    List<CellId> cells,
    Set<EdgeId> windowEdges,
    Map<EdgeId, SlitherlinkEdgeState> candidate,
    SlitherlinkState state,
  ) {
    final topology = puzzle.topology;
    for (final cell in cells) {
      final clue = puzzle.clues[cell];
      if (clue == null) continue;
      final lines = topology
          .edgesAround(cell)
          .where((edge) => candidate[edge] == SlitherlinkEdgeState.line)
          .length;
      if (lines != clue) return false;
    }

    final top = cells.first.row;
    final left = cells.first.column;
    for (var row = top; row <= top + 2; row++) {
      for (var column = left; column <= left + 2; column++) {
        final incident = topology.edgesAt(VertexId(row, column));
        final lines = incident.where((edge) {
          return (candidate[edge] ?? state.stateOf(edge)) ==
              SlitherlinkEdgeState.line;
        }).length;
        if (lines > 2) return false;
        final fullyDecided = incident.every((edge) {
          return candidate.containsKey(edge) ||
              state.stateOf(edge) != SlitherlinkEdgeState.empty;
        });
        if (fullyDecided && lines == 1) return false;
        if (incident.every(windowEdges.contains) && lines != 0 && lines != 2) {
          return false;
        }
      }
    }
    return true;
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
    final propagation = _propagateForSearch(puzzle, input);
    if (propagation == null) return 0;
    final state = propagation;
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

  SlitherlinkState? _propagateForSearch(
    SlitherlinkPuzzle puzzle,
    SlitherlinkState input,
  ) {
    var state = input;
    while (true) {
      final assignments = <EdgeId, SlitherlinkEdgeState>{};
      var contradiction = false;

      void forceEdges(List<EdgeId> edges, SlitherlinkEdgeState target) {
        for (final edge in edges) {
          final existing = assignments[edge];
          if (existing != null && existing != target) {
            contradiction = true;
            return;
          }
          assignments[edge] = target;
        }
      }

      for (final entry in puzzle.clues.entries) {
        final unknown = <EdgeId>[];
        var lines = 0;
        for (final edge in puzzle.topology.edgesAround(entry.key)) {
          switch (state.stateOf(edge)) {
            case SlitherlinkEdgeState.line:
              lines++;
            case SlitherlinkEdgeState.empty:
              unknown.add(edge);
            case SlitherlinkEdgeState.crossed:
              break;
          }
        }
        if (lines > entry.value || lines + unknown.length < entry.value) {
          return null;
        }
        if (unknown.isNotEmpty && lines == entry.value) {
          forceEdges(unknown, SlitherlinkEdgeState.crossed);
        } else if (unknown.isNotEmpty &&
            lines + unknown.length == entry.value) {
          forceEdges(unknown, SlitherlinkEdgeState.line);
        }
        if (contradiction) return null;
      }

      for (var row = 0; row <= puzzle.topology.rows; row++) {
        for (var column = 0; column <= puzzle.topology.columns; column++) {
          final unknown = <EdgeId>[];
          var lines = 0;
          for (final edge in puzzle.topology.edgesAt(VertexId(row, column))) {
            switch (state.stateOf(edge)) {
              case SlitherlinkEdgeState.line:
                lines++;
              case SlitherlinkEdgeState.empty:
                unknown.add(edge);
              case SlitherlinkEdgeState.crossed:
                break;
            }
          }
          if (lines > 2 || (lines == 1 && unknown.isEmpty)) return null;
          if (unknown.isEmpty) continue;
          if (lines == 2 || (lines == 0 && unknown.length == 1)) {
            forceEdges(unknown, SlitherlinkEdgeState.crossed);
          } else if (lines == 1 && unknown.length == 1) {
            forceEdges(unknown, SlitherlinkEdgeState.line);
          }
          if (contradiction) return null;
        }
      }

      final loopClosure = _closedLoopAssignments(puzzle, state);
      if (loopClosure == null) return null;
      for (final edge in loopClosure.keys) {
        forceEdges([edge], SlitherlinkEdgeState.crossed);
      }
      if (contradiction) return null;

      final insideOutside = _insideOutsideAssignments(puzzle, state);
      if (insideOutside == null) return null;
      for (final entry in insideOutside.entries) {
        forceEdges([entry.key], entry.value);
      }
      if (contradiction) return null;

      if (assignments.isEmpty) return state;
      state = state.withEdges(assignments);
    }
  }

  bool _isComplete(SlitherlinkPuzzle puzzle, SlitherlinkState state) {
    if (puzzle.topology.allEdges.any(
      (edge) => state.stateOf(edge) == SlitherlinkEdgeState.empty,
    )) {
      return false;
    }
    return puzzle.check(state).status == CheckStatus.solved;
  }

  EdgeId? _nextUndecidedEdge(
    SlitherlinkPuzzle puzzle,
    SlitherlinkState state, {
    EdgeId? near,
  }) {
    final scores = <EdgeId, int>{};
    void addConstraint(List<EdgeId> edges) {
      var lines = 0;
      final empty = <EdgeId>[];
      for (final edge in edges) {
        switch (state.stateOf(edge)) {
          case SlitherlinkEdgeState.line:
            lines++;
          case SlitherlinkEdgeState.empty:
            empty.add(edge);
          case SlitherlinkEdgeState.crossed:
            break;
        }
      }
      final weight = 4 - empty.length + lines;
      for (final edge in empty) {
        scores.update(edge, (score) => score + weight, ifAbsent: () => weight);
      }
    }

    for (final cell in puzzle.clues.keys) {
      addConstraint(puzzle.topology.edgesAround(cell));
    }
    for (var row = 0; row <= puzzle.topology.rows; row++) {
      for (var column = 0; column <= puzzle.topology.columns; column++) {
        addConstraint(puzzle.topology.edgesAt(VertexId(row, column)));
      }
    }
    EdgeId? selected;
    var highestScore = -1;
    var nearestDistance = 1 << 30;
    for (final entry in scores.entries) {
      final distance = near == null ? 0 : _edgeDistance(near, entry.key);
      if (entry.value > highestScore ||
          (entry.value == highestScore && distance < nearestDistance)) {
        selected = entry.key;
        highestScore = entry.value;
        nearestDistance = distance;
      }
    }
    return selected;
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

final class _ParityUnionFind {
  _ParityUnionFind(int size)
    : _parents = List.generate(size, (index) => index),
      _oppositeToParent = List.filled(size, 0);

  final List<int> _parents;
  final List<int> _oppositeToParent;

  (int, int) find(int node) {
    final parent = _parents[node];
    if (parent == node) return (node, 0);
    final (root, parentParity) = find(parent);
    _oppositeToParent[node] ^= parentParity;
    _parents[node] = root;
    return (root, _oppositeToParent[node]);
  }

  bool join(int first, int second, bool opposite) {
    final (firstRoot, firstParity) = find(first);
    final (secondRoot, secondParity) = find(second);
    final requiredParity = opposite ? 1 : 0;
    if (firstRoot == secondRoot) {
      return firstParity ^ secondParity == requiredParity;
    }
    _parents[firstRoot] = secondRoot;
    _oppositeToParent[firstRoot] = firstParity ^ secondParity ^ requiredParity;
    return true;
  }
}
