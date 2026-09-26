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
}
