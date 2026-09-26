import 'package:puzzle_core/puzzle_core.dart';
import 'package:test/test.dart';

void main() {
  test('session replays, undoes, and redoes puzzle-specific actions', () {
    final puzzle = SlitherlinkPuzzle(
      topology: const GridTopology(rows: 1, columns: 1),
      clues: {const CellId(0, 0): 1},
    );
    var session = PuzzleSession.start(
      initialState: puzzle.initialState,
      reducer: puzzle.reduce,
    );
    const top = EdgeId.horizontal(0, 0);

    session = session.apply(
      const SetSlitherlinkEdge(top, SlitherlinkEdgeState.line),
    );
    expect(session.state.stateOf(top), SlitherlinkEdgeState.line);
    expect(session.stateAfter(0).stateOf(top), SlitherlinkEdgeState.empty);

    session = session.undo();
    expect(session.state.stateOf(top), SlitherlinkEdgeState.empty);
    session = session.redo();
    expect(session.state.stateOf(top), SlitherlinkEdgeState.line);
  });
}
