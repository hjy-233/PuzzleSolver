# PuzzleSolver

A Dart platform for grid logic puzzles. It models a puzzle as topology plus
puzzle-specific state and rules, rather than treating every puzzle as a grid of
buttons.

## Packages

`packages/puzzle_core` is a pure Dart package with no Flutter or server
dependency. It currently provides:

- canonical `CellId`, `EdgeId`, and `VertexId` identifiers;
- rectangular grid adjacency and boundary rules;
- renderer hit targets and puzzle-owned actions;
- immutable action logs with undo, redo, and replay;
- structured, localizable solution steps;
- an edge-first Slitherlink reference implementation.

`apps/puzzle_app` is the Flutter Web player. Its first screen renders and
plays the Slitherlink reference puzzle with edge hit testing, line/cross
interaction, hints, checking, undo, redo, and step replay.

## Development

```sh
cd packages/puzzle_core && dart test
cd ../../apps/puzzle_app && flutter run -d web-server
```

The next core milestone is a second, Cell-first puzzle. It will verify that
the shared layer does not accidentally become specific to line-drawing puzzles.

## Deployment

`project-deployer.json` deploys the Flutter Web player to a 64-bit Raspberry
Pi through ProjectDeployer. It builds an ARM64 image from `Dockerfile`, serves
the generated web files through nginx, and exposes the app on port `18082`.

The deployment manifest keeps the runtime stateless: no volumes or secrets
are required for the current local-only puzzle player.
