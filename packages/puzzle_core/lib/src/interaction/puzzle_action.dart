import '../topology/grid_topology.dart';

/// What the renderer hit. A puzzle maps this to one of its own action types.
sealed class PuzzleTarget {
  const PuzzleTarget();
}

final class CellTarget extends PuzzleTarget {
  const CellTarget(this.cell);

  final CellId cell;
}

final class EdgeTarget extends PuzzleTarget {
  const EdgeTarget(this.edge);

  final EdgeId edge;
}

final class VertexTarget extends PuzzleTarget {
  const VertexTarget(this.vertex);

  final VertexId vertex;
}

enum PointerGesture { primaryTap, secondaryTap, doubleTap, longPress }

/// Marker base class. Concrete actions always belong to a concrete puzzle.
abstract interface class PuzzleAction {
  const PuzzleAction();
}
