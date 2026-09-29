import 'dart:convert';

import 'package:puzzle_core/puzzle_core.dart';

/// Encodes a puzzle and, optionally, its current edge marks into a URL-safe
/// compact value. The payload is validated again when decoded from a URL.
final class SlitherlinkShare {
  const SlitherlinkShare._();

  static String encodePuzzle(SlitherlinkPuzzle puzzle) =>
      PuzzleShareCodec.encode({
        'r': puzzle.topology.rows,
        'c': puzzle.topology.columns,
        'n': [
          for (final entry in puzzle.clues.entries)
            [entry.key.row, entry.key.column, entry.value],
        ],
      });

  static String encodeProgress(SlitherlinkState state) =>
      PuzzleShareCodec.encode([
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
    final value = PuzzleShareCodec.decode(encoded);
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
    final value = PuzzleShareCodec.decode(encoded);
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
}

final class SudokuShare {
  const SudokuShare._();

  static String encodePuzzle(SudokuPuzzle puzzle) => PuzzleShareCodec.encode({
    'n': puzzle.size,
    'g': [
      for (final entry in puzzle.givens.entries)
        [entry.key.row, entry.key.column, entry.value],
    ],
  });

  static SudokuPuzzle decodePuzzle(String encoded) {
    final raw = PuzzleShareCodec.decode(encoded);
    if (raw is! Map<String, dynamic> ||
        raw['n'] is! int ||
        raw['g'] is! List ||
        (raw['g'] as List).length > 81) {
      throw const FormatException('分享链接中的数独题目格式无效。');
    }
    final size = raw['n'] as int;
    if (size != 6 && size != 9) {
      throw const FormatException('分享链接中的数独尺寸无效。');
    }
    final givens = <CellId, int>{};
    for (final clue in raw['g'] as List<dynamic>) {
      final parsed = _parseTriple(clue, size);
      if (givens.containsKey(parsed.$1)) {
        throw const FormatException('分享链接重复定义了数独数字。');
      }
      givens[parsed.$1] = parsed.$2;
    }
    return SudokuPuzzle(size: size, givens: givens);
  }

  static String encodeProgress(SudokuState state) => PuzzleShareCodec.encode({
    'v': [
      for (final entry in state.values.entries)
        [entry.key.row, entry.key.column, entry.value],
    ],
    'm': [
      for (final entry in state.notes.entries)
        if (entry.value.isNotEmpty)
          [entry.key.row, entry.key.column, entry.value.toList()..sort()],
    ],
  });

  static SudokuState decodeProgress(String encoded, SudokuPuzzle puzzle) {
    final raw = PuzzleShareCodec.decode(encoded);
    if (raw is! Map<String, dynamic> ||
        raw['v'] is! List ||
        raw['m'] is! List ||
        (raw['v'] as List).length > puzzle.size * puzzle.size ||
        (raw['m'] as List).length > puzzle.size * puzzle.size) {
      throw const FormatException('分享链接中的数独进度格式无效。');
    }
    final values = <CellId, int>{...puzzle.givens};
    for (final entry in raw['v'] as List<dynamic>) {
      final parsed = _parseTriple(entry, puzzle.size);
      if (puzzle.givens.containsKey(parsed.$1)) continue;
      if (values.containsKey(parsed.$1)) {
        throw const FormatException('分享链接重复定义了数独数字。');
      }
      values[parsed.$1] = parsed.$2;
    }
    if (!puzzle.isConsistent(values)) {
      throw const FormatException('分享链接中的数独进度存在冲突。');
    }
    final notes = <CellId, Set<int>>{};
    for (final entry in raw['m'] as List<dynamic>) {
      if (entry is! List ||
          entry.length != 3 ||
          entry[0] is! int ||
          entry[1] is! int ||
          entry[2] is! List) {
        throw const FormatException('分享链接中的候选笔记格式无效。');
      }
      final cell = CellId(entry[0] as int, entry[1] as int);
      final candidates = (entry[2] as List<dynamic>).toSet();
      if (cell.row < 0 ||
          cell.row >= puzzle.size ||
          cell.column < 0 ||
          cell.column >= puzzle.size ||
          candidates.any(
            (value) => value is! int || value < 1 || value > puzzle.size,
          ) ||
          puzzle.givens.containsKey(cell) ||
          values.containsKey(cell) ||
          notes.containsKey(cell)) {
        throw const FormatException('分享链接包含无效的候选笔记。');
      }
      notes[cell] = candidates.cast<int>();
    }
    return SudokuState(values: values, notes: notes);
  }

  static (CellId, int) _parseTriple(Object? raw, int size) {
    if (raw is! List ||
        raw.length != 3 ||
        raw[0] is! int ||
        raw[1] is! int ||
        raw[2] is! int) {
      throw const FormatException('分享链接中的数独数字格式无效。');
    }
    final cell = CellId(raw[0] as int, raw[1] as int);
    final value = raw[2] as int;
    if (cell.row < 0 ||
        cell.row >= size ||
        cell.column < 0 ||
        cell.column >= size ||
        value < 1 ||
        value > size) {
      throw const FormatException('分享链接包含无效的数独数字。');
    }
    return (cell, value);
  }
}

final class PuzzleShareCodec {
  const PuzzleShareCodec._();

  static String encode(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');

  static Object? decode(String value) {
    try {
      return jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(value))),
      );
    } on FormatException {
      throw const FormatException('分享链接内容损坏或不完整。');
    }
  }
}
