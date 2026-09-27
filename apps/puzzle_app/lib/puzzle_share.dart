import 'dart:convert';

import 'package:puzzle_core/puzzle_core.dart';

/// Encodes a puzzle and, optionally, its current edge marks into a URL-safe
/// compact value. The payload is validated again when decoded from a URL.
final class SlitherlinkShare {
  const SlitherlinkShare._();

  static String encodePuzzle(SlitherlinkPuzzle puzzle) => _encode({
    'r': puzzle.topology.rows,
    'c': puzzle.topology.columns,
    'n': [
      for (final entry in puzzle.clues.entries)
        [entry.key.row, entry.key.column, entry.value],
    ],
  });

  static String encodeProgress(SlitherlinkState state) => _encode([
    for (final entry in state.edges.entries)
      if (entry.value != SlitherlinkEdgeState.empty)
        [
          entry.key.orientation == EdgeOrientation.horizontal ? 0 : 1,
          entry.key.row,
          entry.key.column,
          entry.value == SlitherlinkEdgeState.line ? 1 : 2,
        ],
  ]);

  static SlitherlinkPuzzle decodePuzzle(String encoded) {
    final value = _decode(encoded);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('分享链接中的题目格式无效。');
    }
    final rows = value['r'];
    final columns = value['c'];
    final rawClues = value['n'];
    if (rows is! int ||
        columns is! int ||
        rows < 1 ||
        columns < 1 ||
        rows * columns > 100 ||
        rawClues is! List) {
      throw const FormatException('分享链接中的棋盘尺寸无效。');
    }
    final topology = GridTopology(rows: rows, columns: columns);
    final clues = <CellId, int>{};
    for (final raw in rawClues) {
      if (raw is! List || raw.length != 3) {
        throw const FormatException('分享链接中的数字格格式无效。');
      }
      final row = raw[0];
      final column = raw[1];
      final clue = raw[2];
      if (row is! int || column is! int || clue is! int) {
        throw const FormatException('分享链接中的数字格格式无效。');
      }
      final cell = CellId(row, column);
      if (!topology.containsCell(cell) || clue < 0 || clue > 4) {
        throw const FormatException('分享链接包含无效的数字格。');
      }
      clues[cell] = clue;
    }
    return SlitherlinkPuzzle(topology: topology, clues: clues);
  }

  static SlitherlinkState decodeProgress(
    String encoded,
    GridTopology topology,
  ) {
    final value = _decode(encoded);
    if (value is! List ||
        value.length >
            2 * topology.rows * topology.columns +
                topology.rows +
                topology.columns) {
      throw const FormatException('分享链接中的进度格式无效。');
    }
    final edges = <EdgeId, SlitherlinkEdgeState>{};
    for (final raw in value) {
      if (raw is! List || raw.length != 4) {
        throw const FormatException('分享链接中的边状态格式无效。');
      }
      final orientation = raw[0];
      final row = raw[1];
      final column = raw[2];
      final state = raw[3];
      if (orientation is! int || row is! int || column is! int) {
        throw const FormatException('分享链接中的边状态格式无效。');
      }
      final edge = switch (orientation) {
        0 => EdgeId.horizontal(row, column),
        1 => EdgeId.vertical(row, column),
        _ => throw const FormatException('分享链接中的边方向无效。'),
      };
      if (!topology.containsEdge(edge) || (state != 1 && state != 2)) {
        throw const FormatException('分享链接包含无效的边状态。');
      }
      edges[edge] = state == 1
          ? SlitherlinkEdgeState.line
          : SlitherlinkEdgeState.crossed;
    }
    return SlitherlinkState(edges);
  }

  static String _encode(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');

  static Object? _decode(String value) {
    try {
      return jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(value))),
      );
    } on FormatException {
      throw const FormatException('分享链接内容损坏或不完整。');
    }
  }
}
