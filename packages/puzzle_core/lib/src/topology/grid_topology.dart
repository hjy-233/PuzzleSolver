/// A grid location that identifies one square face in a rectangular topology.
final class CellId {
  const CellId(this.row, this.column);

  final int row;
  final int column;

  @override
  bool operator ==(Object other) =>
      other is CellId && row == other.row && column == other.column;

  @override
  int get hashCode => Object.hash(row, column);

  @override
  String toString() => 'Cell($row, $column)';
}

/// A grid point at the end of one or more edges.
final class VertexId {
  const VertexId(this.row, this.column);

  final int row;
  final int column;

  @override
  bool operator ==(Object other) =>
      other is VertexId && row == other.row && column == other.column;

  @override
  int get hashCode => Object.hash(row, column);

  @override
  String toString() => 'Vertex($row, $column)';
}

enum EdgeOrientation { horizontal, vertical }

/// A unique line segment. Horizontal edges use `row: 0...rows` and
/// `column: 0..<columns`; vertical edges use `row: 0..<rows` and
/// `column: 0...columns`.
final class EdgeId {
  const EdgeId.horizontal(this.row, this.column)
    : orientation = EdgeOrientation.horizontal;

  const EdgeId.vertical(this.row, this.column)
    : orientation = EdgeOrientation.vertical;

  final EdgeOrientation orientation;
  final int row;
  final int column;

  @override
  bool operator ==(Object other) =>
      other is EdgeId &&
      orientation == other.orientation &&
      row == other.row &&
      column == other.column;

  @override
  int get hashCode => Object.hash(orientation, row, column);

  @override
  String toString() => '${orientation.name}Edge($row, $column)';
}

/// Shared geometry only. It deliberately contains no puzzle state or UI code.
final class GridTopology {
  const GridTopology({required this.rows, required this.columns})
    : assert(rows > 0),
      assert(columns > 0);

  final int rows;
  final int columns;

  Iterable<EdgeId> get allEdges sync* {
    for (var row = 0; row <= rows; row++) {
      for (var column = 0; column < columns; column++) {
        yield EdgeId.horizontal(row, column);
      }
    }
    for (var row = 0; row < rows; row++) {
      for (var column = 0; column <= columns; column++) {
        yield EdgeId.vertical(row, column);
      }
    }
  }

  bool containsCell(CellId cell) =>
      cell.row >= 0 &&
      cell.row < rows &&
      cell.column >= 0 &&
      cell.column < columns;

  bool containsVertex(VertexId vertex) =>
      vertex.row >= 0 &&
      vertex.row <= rows &&
      vertex.column >= 0 &&
      vertex.column <= columns;

  bool containsEdge(EdgeId edge) => switch (edge.orientation) {
    EdgeOrientation.horizontal =>
      edge.row >= 0 &&
          edge.row <= rows &&
          edge.column >= 0 &&
          edge.column < columns,
    EdgeOrientation.vertical =>
      edge.row >= 0 &&
          edge.row < rows &&
          edge.column >= 0 &&
          edge.column <= columns,
  };

  List<EdgeId> edgesAround(CellId cell) {
    _requireCell(cell);
    return [
      EdgeId.horizontal(cell.row, cell.column),
      EdgeId.vertical(cell.row, cell.column + 1),
      EdgeId.horizontal(cell.row + 1, cell.column),
      EdgeId.vertical(cell.row, cell.column),
    ];
  }

  List<CellId> cellsBeside(EdgeId edge) {
    _requireEdge(edge);
    return switch (edge.orientation) {
      EdgeOrientation.horizontal => [
        if (edge.row > 0) CellId(edge.row - 1, edge.column),
        if (edge.row < rows) CellId(edge.row, edge.column),
      ],
      EdgeOrientation.vertical => [
        if (edge.column > 0) CellId(edge.row, edge.column - 1),
        if (edge.column < columns) CellId(edge.row, edge.column),
      ],
    };
  }

  List<VertexId> verticesOf(EdgeId edge) {
    _requireEdge(edge);
    return switch (edge.orientation) {
      EdgeOrientation.horizontal => [
        VertexId(edge.row, edge.column),
        VertexId(edge.row, edge.column + 1),
      ],
      EdgeOrientation.vertical => [
        VertexId(edge.row, edge.column),
        VertexId(edge.row + 1, edge.column),
      ],
    };
  }

  void _requireCell(CellId cell) {
    if (!containsCell(cell)) {
      throw ArgumentError.value(cell, 'cell', 'Outside this grid');
    }
  }

  void _requireEdge(EdgeId edge) {
    if (!containsEdge(edge)) {
      throw ArgumentError.value(edge, 'edge', 'Outside this grid');
    }
  }
}
