# PuzzleSolver

A Dart platform for grid logic puzzles. It models a puzzle as topology plus
puzzle-specific state and rules, rather than treating every puzzle as a grid of
buttons.

## Current package

`packages/puzzle_core` is a pure Dart package with no Flutter or server
dependency. It currently provides:

- canonical `CellId`, `EdgeId`, and `VertexId` identifiers;
- rectangular grid adjacency and boundary rules;
- renderer hit targets and puzzle-owned actions;
- immutable action logs with undo, redo, and replay;
- structured, localizable solution steps;
- an edge-first Slitherlink reference implementation.

## Development

```sh
cd packages/puzzle_core
dart pub get
dart format --set-exit-if-changed lib test
dart analyze
dart test
```

The Flutter app will be added after the core supports a second, Cell-first
puzzle. This makes sure the shared layer does not accidentally become specific
to line-drawing puzzles.
