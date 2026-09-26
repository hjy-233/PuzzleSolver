import '../interaction/puzzle_action.dart';

typedef PuzzleReducer<S, A extends PuzzleAction> =
    S Function(S state, A action);

/// Immutable state plus a replayable history. The core never interprets [S].
final class PuzzleSession<S, A extends PuzzleAction> {
  const PuzzleSession._({
    required this.initialState,
    required this.state,
    required this.reducer,
    required this.appliedActions,
    required this.redoActions,
  });

  factory PuzzleSession.start({
    required S initialState,
    required PuzzleReducer<S, A> reducer,
  }) => PuzzleSession._(
    initialState: initialState,
    state: initialState,
    reducer: reducer,
    appliedActions: const [],
    redoActions: const [],
  );

  final S initialState;
  final S state;
  final PuzzleReducer<S, A> reducer;
  final List<A> appliedActions;
  final List<A> redoActions;

  bool get canUndo => appliedActions.isNotEmpty;
  bool get canRedo => redoActions.isNotEmpty;

  PuzzleSession<S, A> apply(A action) => PuzzleSession._(
    initialState: initialState,
    state: reducer(state, action),
    reducer: reducer,
    appliedActions: [...appliedActions, action],
    redoActions: const [],
  );

  PuzzleSession<S, A> undo() {
    if (!canUndo) return this;
    final restoredActions = appliedActions.sublist(
      0,
      appliedActions.length - 1,
    );
    return PuzzleSession._(
      initialState: initialState,
      state: _replay(restoredActions),
      reducer: reducer,
      appliedActions: restoredActions,
      redoActions: [appliedActions.last, ...redoActions],
    );
  }

  PuzzleSession<S, A> redo() {
    if (!canRedo) return this;
    final action = redoActions.first;
    return PuzzleSession._(
      initialState: initialState,
      state: reducer(state, action),
      reducer: reducer,
      appliedActions: [...appliedActions, action],
      redoActions: redoActions.sublist(1),
    );
  }

  S stateAfter(int actionCount) {
    if (actionCount < 0 || actionCount > appliedActions.length) {
      throw RangeError.range(
        actionCount,
        0,
        appliedActions.length,
        'actionCount',
      );
    }
    return _replay(appliedActions.take(actionCount));
  }

  S _replay(Iterable<A> actions) => actions.fold(initialState, reducer);
}
