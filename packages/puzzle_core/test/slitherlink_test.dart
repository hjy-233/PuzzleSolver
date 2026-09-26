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
}
