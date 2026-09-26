# puzzle_core

Pure Dart foundation for grid logic puzzles. It has no Flutter, backend, or
shared `CellState` dependency.

## What is shared

- rectangular `GridTopology` with canonical `CellId`, `EdgeId`, and `VertexId`;
- renderer hit targets and pointer gestures;
- immutable action-log sessions with undo, redo, and replay;
- structured `SolveStep` data for localized, inspectable explanations.

## What stays puzzle-specific

Each puzzle owns its state, action types, rules, checker, and solver. The first
reference implementation is Slitherlink, which demonstrates that an edge state
is not attached to either adjacent cell.

Run checks with:

```sh
dart format --set-exit-if-changed lib test
dart analyze
dart test
```
