import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:puzzle_core/puzzle_core.dart';

final class SlitherlinkApi {
  const SlitherlinkApi();

  Future<SlitherlinkPuzzle> generate({
    required int rows,
    required int columns,
    required PuzzleDifficulty difficulty,
    required bool includeBlankCells,
    required double clueDensity,
    required bool useServer,
    VoidCallback? onLocalFallback,
  }) async {
    final request = <String, Object?>{
      'rows': rows,
      'columns': columns,
      'difficulty': difficulty.name,
      'includeBlankCells': includeBlankCells,
      'clueDensity': clueDensity,
    };
    late final Map<String, dynamic> response;
    if (!useServer) {
      response = await compute(_generateLocally, request);
    } else {
      try {
        response = await _post('/api/puzzles/slitherlink/generate', request);
      } on _UseBrowserCompute {
        onLocalFallback?.call();
        await Future<void>.delayed(const Duration(milliseconds: 40));
        response = await compute(_generateLocally, request);
      }
    }
    return _parsePuzzle(response);
  }

  Future<SlitherlinkSolveResult> solve(
    SlitherlinkPuzzle puzzle,
    SlitherlinkState state, {
    required bool useServer,
    VoidCallback? onLocalFallback,
  }) async {
    final request = <String, Object?>{
      ..._serializePuzzle(puzzle),
      'edges': _serializeState(state),
    };
    late final Map<String, dynamic> response;
    if (!useServer) {
      response = await compute(_solveLocally, request);
    } else {
      try {
        response = await _post('/api/puzzles/slitherlink/solve', request);
      } on _UseBrowserCompute {
        onLocalFallback?.call();
        await Future<void>.delayed(const Duration(milliseconds: 40));
        response = await compute(_solveLocally, request);
      }
    }
    final solution = _parseState(response['state'], puzzle.topology);
    final steps = (response['steps'] as List<dynamic>)
        .map((step) => _parseStep(step as Map<String, dynamic>))
        .toList();
    return SlitherlinkSolveResult(
      state: solution,
      steps: steps,
      solutionCount: response['solutionCount'] as int,
    );
  }

  Future<CheckResult> check(
    SlitherlinkPuzzle puzzle,
    SlitherlinkState state,
  ) async => puzzle.check(state);

  Future<DateTime> redeemInvitation(String code) async {
    final response = await _post('/api/access/redeem', {'code': code});
    if (response['authorized'] != true) {
      throw const FormatException('邀请码验证失败。');
    }
    final expiresAt = response['expiresAt'];
    if (expiresAt is! String) {
      throw const FormatException('服务器没有返回邀请码有效期。');
    }
    final expiration = DateTime.tryParse(expiresAt);
    if (expiration == null) {
      throw const FormatException('服务器返回的邀请码有效期无效。');
    }
    return expiration;
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, Object?> payload,
  ) async {
    final encoded = jsonEncode(payload);
    const configuredBaseUrl = String.fromEnvironment('PUZZLE_API_BASE_URL');
    final baseUri = configuredBaseUrl.isNotEmpty
        ? Uri.parse(configuredBaseUrl)
        : Uri.base.host == 'localhost' || Uri.base.host == '127.0.0.1'
        ? Uri.parse('http://pi.local:18082')
        : Uri.base;
    final response = await http
        .post(
          baseUri.resolve(path),
          headers: const {'Content-Type': 'application/json'},
          body: encoded,
        )
        .timeout(const Duration(seconds: 90));
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('服务器返回了无效数据。');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final code = decoded['code'];
      if ((response.statusCode == 429 &&
              (code == 'daily_quota_exceeded' || code == 'rate_limited')) ||
          (response.statusCode == 503 &&
              (code == 'server_busy' || code == 'generation_failed'))) {
        throw const _UseBrowserCompute();
      }
      throw StateError(decoded['error'] as String? ?? '服务器请求失败。');
    }
    return decoded;
  }

  Map<String, Object?> _serializePuzzle(SlitherlinkPuzzle puzzle) => {
    'rows': puzzle.topology.rows,
    'columns': puzzle.topology.columns,
    'clues': [
      for (final entry in puzzle.clues.entries)
        {
          'row': entry.key.row,
          'column': entry.key.column,
          'value': entry.value,
        },
    ],
  };

  List<Map<String, Object?>> _serializeState(SlitherlinkState state) => [
    for (final entry in state.edges.entries)
      {
        'orientation': entry.key.orientation.name,
        'row': entry.key.row,
        'column': entry.key.column,
        'state': entry.value.name,
      },
  ];

  SlitherlinkPuzzle _parsePuzzle(Map<String, dynamic> response) {
    final rows = response['rows'] as int;
    final columns = response['columns'] as int;
    final topology = GridTopology(rows: rows, columns: columns);
    final clues = <CellId, int>{};
    for (final clue in response['clues'] as List<dynamic>) {
      final item = clue as Map<String, dynamic>;
      clues[CellId(item['row'] as int, item['column'] as int)] =
          item['value'] as int;
    }
    return SlitherlinkPuzzle(topology: topology, clues: clues);
  }

  SlitherlinkState _parseState(Object? raw, GridTopology topology) {
    if (raw is! List) throw const FormatException('边状态格式错误。');
    final edges = <EdgeId, SlitherlinkEdgeState>{};
    for (final item in raw) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('边状态格式错误。');
      }
      final row = item['row'] as int;
      final column = item['column'] as int;
      final edge = switch (item['orientation']) {
        'horizontal' => EdgeId.horizontal(row, column),
        'vertical' => EdgeId.vertical(row, column),
        _ => throw const FormatException('边方向无效。'),
      };
      if (!topology.containsEdge(edge)) {
        throw const FormatException('边超出了棋盘范围。');
      }
      edges[edge] = SlitherlinkEdgeState.values.byName(item['state'] as String);
    }
    return SlitherlinkState(edges);
  }

  SolveStep<SlitherlinkAction> _parseStep(Map<String, dynamic> data) {
    final actions = <SlitherlinkAction>[];
    for (final raw in data['actions'] as List<dynamic>) {
      final action = raw as Map<String, dynamic>;
      final edgeData = action['edge'] as Map<String, dynamic>;
      final edge = switch (edgeData['orientation']) {
        'horizontal' => EdgeId.horizontal(
          edgeData['row'] as int,
          edgeData['column'] as int,
        ),
        'vertical' => EdgeId.vertical(
          edgeData['row'] as int,
          edgeData['column'] as int,
        ),
        _ => throw const FormatException('步骤边方向无效。'),
      };
      actions.add(
        SetSlitherlinkEdge(
          edge,
          SlitherlinkEdgeState.values.byName(action['state'] as String),
        ),
      );
    }
    return SolveStep(
      ruleId: data['ruleId'] as String,
      highlights: [
        for (final raw in data['highlights'] as List<dynamic>)
          _parseTarget(raw as Map<String, dynamic>),
      ],
      actions: actions,
      arguments: Map<String, Object?>.from(data['arguments'] as Map),
    );
  }

  PuzzleTarget _parseTarget(Map<String, dynamic> data) =>
      switch (data['type']) {
        'cell' => CellTarget(CellId(data['row'] as int, data['column'] as int)),
        'edge' => EdgeTarget(switch (data['orientation']) {
          'horizontal' => EdgeId.horizontal(
            data['row'] as int,
            data['column'] as int,
          ),
          'vertical' => EdgeId.vertical(
            data['row'] as int,
            data['column'] as int,
          ),
          _ => throw const FormatException('步骤边方向无效。'),
        }),
        'vertex' => VertexTarget(
          VertexId(data['row'] as int, data['column'] as int),
        ),
        _ => throw const FormatException('步骤高亮目标无效。'),
      };
}

final class _UseBrowserCompute implements Exception {
  const _UseBrowserCompute();
}

Map<String, dynamic> _generateLocally(Map<String, Object?> request) {
  final rows = request['rows']! as int;
  final columns = request['columns']! as int;
  final generated = const SlitherlinkGenerator().generate(
    SlitherlinkGenerationOptions(
      rows: rows,
      columns: columns,
      difficulty: PuzzleDifficulty.values.byName(
        request['difficulty']! as String,
      ),
      includeBlankCells: request['includeBlankCells']! as bool,
      clueDensity: request['clueDensity']! as double,
      includeSolveSteps: false,
    ),
  );
  return {
    'rows': rows,
    'columns': columns,
    'clues': [
      for (final entry in generated.puzzle.clues.entries)
        {
          'row': entry.key.row,
          'column': entry.key.column,
          'value': entry.value,
        },
    ],
  };
}

Map<String, dynamic> _solveLocally(Map<String, Object?> request) {
  final rows = request['rows']! as int;
  final columns = request['columns']! as int;
  final topology = GridTopology(rows: rows, columns: columns);
  final clues = <CellId, int>{};
  for (final raw in request['clues']! as List<dynamic>) {
    final clue = raw as Map<String, dynamic>;
    clues[CellId(clue['row']! as int, clue['column']! as int)] =
        clue['value']! as int;
  }
  final puzzle = SlitherlinkPuzzle(topology: topology, clues: clues);
  final edges = <EdgeId, SlitherlinkEdgeState>{};
  for (final raw in request['edges']! as List<dynamic>) {
    final item = raw as Map<String, dynamic>;
    final row = item['row']! as int;
    final column = item['column']! as int;
    final edge = switch (item['orientation']) {
      'horizontal' => EdgeId.horizontal(row, column),
      'vertical' => EdgeId.vertical(row, column),
      _ => throw const FormatException('边方向无效。'),
    };
    edges[edge] = SlitherlinkEdgeState.values.byName(item['state']! as String);
  }
  final area = rows * columns;
  final result = SlitherlinkSolver(
    maxSearchNodes: area <= 25
        ? 20000
        : area <= 64
        ? 8000
        : 2500,
  ).solve(puzzle, initialState: SlitherlinkState(edges));
  return {
    'solutionCount': result.solutionCount,
    'state': [
      for (final entry in result.state.edges.entries)
        {
          'orientation': entry.key.orientation.name,
          'row': entry.key.row,
          'column': entry.key.column,
          'state': entry.value.name,
        },
    ],
    'steps': [
      for (final step in result.steps)
        {
          'ruleId': step.ruleId,
          'highlights': [
            for (final target in step.highlights)
              switch (target) {
                CellTarget(:final cell) => {
                  'type': 'cell',
                  'row': cell.row,
                  'column': cell.column,
                },
                EdgeTarget(:final edge) => {
                  'type': 'edge',
                  'orientation': edge.orientation.name,
                  'row': edge.row,
                  'column': edge.column,
                },
                VertexTarget(:final vertex) => {
                  'type': 'vertex',
                  'row': vertex.row,
                  'column': vertex.column,
                },
              },
          ],
          'actions': [
            for (final action in step.actions)
              if (action is SetSlitherlinkEdge)
                {
                  'edge': {
                    'orientation': action.edge.orientation.name,
                    'row': action.edge.row,
                    'column': action.edge.column,
                  },
                  'state': action.state.name,
                },
          ],
          'arguments': step.arguments,
        },
    ],
  };
}
