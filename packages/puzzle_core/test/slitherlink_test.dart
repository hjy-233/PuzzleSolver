import 'package:puzzle_core/puzzle_core.dart';
import 'package:test/test.dart';

void main() {
  final puzzle = SlitherlinkPuzzle(
    topology: const GridTopology(rows: 1, columns: 1),
    clues: {const CellId(0, 0): 1},
  );

  test('hint crosses every remaining edge once a clue is reached', () {
    final state = puzzle.reduce(
      puzzle.initialState,
      const SetSlitherlinkEdge(
        EdgeId.horizontal(0, 0),
        SlitherlinkEdgeState.line,
      ),
    );

    final hint = puzzle.hint(state);
    expect(hint?.ruleId, 'slitherlink.clueReached');
    expect(hint?.actions, hasLength(3));
    expect(
      hint?.actions.every((action) => action is SetSlitherlinkEdge),
      isTrue,
    );
  });

  test('checker rejects more lines than a clue permits', () {
    var state = puzzle.initialState;
    state = puzzle.reduce(
      state,
      const SetSlitherlinkEdge(
        EdgeId.horizontal(0, 0),
        SlitherlinkEdgeState.line,
      ),
    );
    state = puzzle.reduce(
      state,
      const SetSlitherlinkEdge(
        EdgeId.horizontal(1, 0),
        SlitherlinkEdgeState.line,
      ),
    );

    expect(puzzle.check(state).status, CheckStatus.invalid);
  });

  test('checker requires one closed loop after every edge is decided', () {
    final loopPuzzle = SlitherlinkPuzzle(
      topology: const GridTopology(rows: 1, columns: 1),
      clues: {const CellId(0, 0): 4},
    );
    var state = loopPuzzle.initialState;
    for (final edge in loopPuzzle.topology.allEdges) {
      state = loopPuzzle.reduce(
        state,
        SetSlitherlinkEdge(edge, SlitherlinkEdgeState.line),
      );
    }

    expect(loopPuzzle.check(state).status, CheckStatus.solved);
  });

  test('checker accepts a valid loop without crossing every unused edge', () {
    const topology = GridTopology(rows: 2, columns: 2);
    final solution = SlitherlinkState({
      const EdgeId.horizontal(0, 0): SlitherlinkEdgeState.line,
      const EdgeId.vertical(0, 1): SlitherlinkEdgeState.line,
      const EdgeId.horizontal(1, 0): SlitherlinkEdgeState.line,
      const EdgeId.vertical(0, 0): SlitherlinkEdgeState.line,
    });
    final puzzle = SlitherlinkPuzzle(
      topology: topology,
      clues: {
        for (var row = 0; row < topology.rows; row++)
          for (var column = 0; column < topology.columns; column++)
            CellId(row, column): topology
                .edgesAround(CellId(row, column))
                .where(
                  (edge) => solution.stateOf(edge) == SlitherlinkEdgeState.line,
                )
                .length,
      },
    );

    expect(puzzle.check(solution).status, CheckStatus.solved);
  });

  test('primary and secondary taps keep line and cross actions separate', () {
    const edge = EdgeId.horizontal(0, 0);
    var state = puzzle.initialState;

    final first = puzzle.actionFor(
      const EdgeTarget(edge),
      PointerGesture.primaryTap,
      state,
    )!;
    state = puzzle.reduce(state, first);
    expect(state.stateOf(edge), SlitherlinkEdgeState.line);

    final second = puzzle.actionFor(
      const EdgeTarget(edge),
      PointerGesture.secondaryTap,
      state,
    )!;
    state = puzzle.reduce(state, second);
    expect(state.stateOf(edge), SlitherlinkEdgeState.crossed);

    final third = puzzle.actionFor(
      const EdgeTarget(edge),
      PointerGesture.secondaryTap,
      state,
    )!;
    state = puzzle.reduce(state, third);
    expect(state.stateOf(edge), SlitherlinkEdgeState.empty);
  });

  test(
    'generator produces a uniquely solvable puzzle with explainable steps',
    () {
      final generated = const SlitherlinkGenerator().generate(
        const SlitherlinkGenerationOptions(rows: 3, columns: 3, seed: 42),
      );

      expect(generated.solveResult.hasUniqueSolution, isTrue);
      expect(generated.puzzle.clues.length, lessThan(9));
      expect(
        generated.puzzle.check(generated.solveResult.state).status,
        CheckStatus.solved,
      );
      expect(generated.solveResult.steps, isNotEmpty);
      expect(
        generated.solveResult.steps.every(
          (step) => step.ruleId.startsWith('slitherlink.'),
        ),
        isTrue,
      );

      var replayed = generated.puzzle.initialState;
      for (final step in generated.solveResult.steps) {
        final cellTarget = step.highlights.whereType<CellTarget>().firstOrNull;
        if (cellTarget != null) {
          final lines = generated.puzzle.topology
              .edgesAround(cellTarget.cell)
              .where(
                (edge) => replayed.stateOf(edge) == SlitherlinkEdgeState.line,
              )
              .length;
          expect(lines, step.arguments['lines']);
        }
        final vertexTarget = step.highlights
            .whereType<VertexTarget>()
            .firstOrNull;
        if (vertexTarget != null && step.arguments.containsKey('lines')) {
          final lines = generated.puzzle.topology
              .edgesAt(vertexTarget.vertex)
              .where(
                (edge) => replayed.stateOf(edge) == SlitherlinkEdgeState.line,
              )
              .length;
          expect(lines, step.arguments['lines']);
        }
        for (final action in step.actions) {
          replayed = generated.puzzle.reduce(replayed, action);
        }
      }
      expect(generated.puzzle.check(replayed).status, CheckStatus.solved);
    },
  );

  test('generator honors Slitherlink-specific generation options', () {
    final generated = const SlitherlinkGenerator().generate(
      const SlitherlinkGenerationOptions(
        rows: 3,
        columns: 3,
        difficulty: PuzzleDifficulty.easy,
        includeBlankCells: false,
        seed: 7,
      ),
    );

    expect(generated.puzzle.clues, hasLength(9));
    expect(generated.solveResult.hasUniqueSolution, isTrue);
  });

  test('clue density controls blank count and hard mode avoids easy clues', () {
    const generator = SlitherlinkGenerator();
    final sparse = generator.generate(
      const SlitherlinkGenerationOptions(
        rows: 5,
        columns: 5,
        difficulty: PuzzleDifficulty.normal,
        clueDensity: 0.3,
        includeSolveSteps: false,
        seed: 31,
      ),
    );
    final dense = generator.generate(
      const SlitherlinkGenerationOptions(
        rows: 5,
        columns: 5,
        difficulty: PuzzleDifficulty.normal,
        clueDensity: 0.8,
        includeSolveSteps: false,
        seed: 31,
      ),
    );
    final hard = generator.generate(
      const SlitherlinkGenerationOptions(
        rows: 5,
        columns: 5,
        difficulty: PuzzleDifficulty.hard,
        clueDensity: 0.55,
        includeSolveSteps: false,
        seed: 31,
      ),
    );

    expect(sparse.puzzle.clues.length, lessThan(dense.puzzle.clues.length));
    final hardEasyClueRatio =
        hard.puzzle.clues.values
            .where((clue) => clue == 0 || clue == 3)
            .length /
        hard.puzzle.clues.length;
    final sparseEasyClueRatio =
        sparse.puzzle.clues.values
            .where((clue) => clue == 0 || clue == 3)
            .length /
        sparse.puzzle.clues.length;
    expect(hardEasyClueRatio, lessThanOrEqualTo(sparseEasyClueRatio));
    expect(const SlitherlinkSolver().countSolutions(sparse.puzzle), 1);
    expect(const SlitherlinkSolver().countSolutions(dense.puzzle), 1);
    expect(const SlitherlinkSolver().countSolutions(hard.puzzle), 1);
  });

  test('fast generation path proves the returned puzzle is unique', () {
    final generated = const SlitherlinkGenerator().generate(
      const SlitherlinkGenerationOptions(
        rows: 3,
        columns: 3,
        difficulty: PuzzleDifficulty.normal,
        includeSolveSteps: false,
        seed: 19,
      ),
    );

    expect(generated.solveResult.steps, isEmpty);
    expect(const SlitherlinkSolver().countSolutions(generated.puzzle), 1);
  });

  test('fast generator remains reliable across common 5x5 seeds', () {
    const generator = SlitherlinkGenerator();
    for (var seed = 0; seed < 8; seed++) {
      for (final difficulty in [
        PuzzleDifficulty.normal,
        PuzzleDifficulty.hard,
      ]) {
        final generated = generator.generate(
          SlitherlinkGenerationOptions(
            rows: 5,
            columns: 5,
            difficulty: difficulty,
            includeSolveSteps: false,
            seed: seed,
          ),
        );
        expect(
          generated.solveResult.hasUniqueSolution,
          isTrue,
          reason: 'seed=$seed, difficulty=$difficulty',
        );
      }
    }
  });

  test('fast generation keeps normal and hard tiers meaningfully distinct', () {
    const generator = SlitherlinkGenerator();
    GeneratedSlitherlinkPuzzle generate(PuzzleDifficulty difficulty) =>
        generator.generate(
          SlitherlinkGenerationOptions(
            rows: 5,
            columns: 5,
            difficulty: difficulty,
            includeSolveSteps: false,
            seed: 23,
          ),
        );

    final easy = generate(PuzzleDifficulty.easy);
    final normal = generate(PuzzleDifficulty.normal);
    final hard = generate(PuzzleDifficulty.hard);

    expect(
      easy.puzzle.clues.length - normal.puzzle.clues.length,
      greaterThanOrEqualTo(4),
    );
    expect(
      normal.puzzle.clues.length - hard.puzzle.clues.length,
      greaterThanOrEqualTo(0),
    );
    final normalEasyClueRatio =
        normal.puzzle.clues.values
            .where((clue) => clue == 0 || clue == 3)
            .length /
        normal.puzzle.clues.length;
    final hardEasyClueRatio =
        hard.puzzle.clues.values
            .where((clue) => clue == 0 || clue == 3)
            .length /
        hard.puzzle.clues.length;
    expect(hardEasyClueRatio, lessThanOrEqualTo(normalEasyClueRatio));
    for (final puzzle in [easy, normal, hard]) {
      expect(const SlitherlinkSolver().countSolutions(puzzle.puzzle), 1);
    }
  });

  test('difficulty tiers produce increasing reasoning demands', () {
    final generator = const SlitherlinkGenerator();
    final easy = generator.generate(
      const SlitherlinkGenerationOptions(
        rows: 5,
        columns: 5,
        difficulty: PuzzleDifficulty.easy,
        seed: 23,
      ),
    );
    final normal = generator.generate(
      const SlitherlinkGenerationOptions(
        rows: 5,
        columns: 5,
        difficulty: PuzzleDifficulty.normal,
        seed: 23,
      ),
    );
    final hard = generator.generate(
      const SlitherlinkGenerationOptions(
        rows: 5,
        columns: 5,
        difficulty: PuzzleDifficulty.hard,
        seed: 23,
      ),
    );

    expect(easy.puzzle.clues.length, greaterThan(normal.puzzle.clues.length));
    expect(normal.puzzle.clues.length, greaterThan(hard.puzzle.clues.length));
    expect(
      _countAssumptions(normal) - _countAssumptions(easy),
      greaterThanOrEqualTo(2),
    );
    expect(
      _countAssumptions(hard) - _countAssumptions(normal),
      greaterThanOrEqualTo(2),
    );
    expect(easy.solveResult.hasUniqueSolution, isTrue);
    expect(normal.solveResult.hasUniqueSolution, isTrue);
    expect(hard.solveResult.hasUniqueSolution, isTrue);
  });

  test('small custom boards still generate a valid hard puzzle', () {
    final generated = const SlitherlinkGenerator().generate(
      const SlitherlinkGenerationOptions(
        rows: 3,
        columns: 3,
        difficulty: PuzzleDifficulty.hard,
        seed: 7,
      ),
    );

    expect(generated.solveResult.hasUniqueSolution, isTrue);
    expect(
      generated.puzzle.check(generated.solveResult.state).status,
      CheckStatus.solved,
    );
  });
}

int _countAssumptions(GeneratedSlitherlinkPuzzle generated) => generated
    .solveResult
    .steps
    .where((step) => step.ruleId == 'slitherlink.assumptionContradiction')
    .length;
