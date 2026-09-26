import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:isolate';

import 'package:puzzle_core/puzzle_core.dart';

const rootDirectory = String.fromEnvironment(
  'PUZZLE_WEB_ROOT',
  defaultValue: '/srv/puzzle-solver',
);
const port = 8080;

Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  await for (final request in server) {
    unawaited(_serve(request));
  }
}

Future<void> _serve(HttpRequest request) async {
  if (request.uri.path.startsWith('/api/')) {
    await _serveApi(request);
    return;
  }
  if (request.method != 'GET' && request.method != 'HEAD') {
    request.response
      ..statusCode = HttpStatus.methodNotAllowed
      ..close();
    return;
  }

  final relativePath = request.uri.pathSegments
      .where(
        (segment) => segment.isNotEmpty && segment != '.' && segment != '..',
      )
      .join('/');
  final requestedFile = File(
    '$rootDirectory/${relativePath.isEmpty ? 'index.html' : relativePath}',
  );
  final file = await requestedFile.exists()
      ? requestedFile
      : File('$rootDirectory/index.html');

  request.response.headers.contentType = _contentTypeFor(file.path);
  request.response.headers.set(
    HttpHeaders.cacheControlHeader,
    'public, max-age=300',
  );
  if (request.method == 'HEAD') {
    await request.response.close();
    return;
  }
  await file.openRead().pipe(request.response);
}

Future<void> _serveApi(HttpRequest request) async {
  request.response.headers.contentType = ContentType.json;
  final origin = request.headers.value('origin');
  if (origin != null && _isLocalDevelopmentOrigin(origin)) {
    request.response.headers.set('Access-Control-Allow-Origin', origin);
    request.response.headers.set(
      'Access-Control-Allow-Methods',
      'POST, OPTIONS',
    );
    request.response.headers.set(
      'Access-Control-Allow-Headers',
      'Content-Type',
    );
  }
  if (request.method == 'OPTIONS') {
    request.response.statusCode = HttpStatus.noContent;
    await request.response.close();
    return;
  }
  if (request.method != 'POST') {
    await _writeJson(request.response, HttpStatus.methodNotAllowed, {
      'error': 'Only POST is supported for this API.',
    });
    return;
  }

  try {
    final body = await _readJsonObject(request);
    final path = request.uri.path;
    final payload = await Isolate.run(() => _dispatchApi(path, body));
    if (payload == null) {
      await _writeJson(request.response, HttpStatus.notFound, {
        'error': 'Unknown API endpoint.',
      });
      return;
    }
    await _writeJson(request.response, HttpStatus.ok, payload);
  } on FormatException catch (error) {
    await _writeJson(request.response, HttpStatus.badRequest, {
      'error': error.message,
    });
  } on ArgumentError catch (error) {
    await _writeJson(request.response, HttpStatus.badRequest, {
      'error': error.message ?? 'Invalid request.',
    });
  } on StateError catch (error) {
    await _writeJson(request.response, HttpStatus.unprocessableEntity, {
      'error': error.message,
    });
  } catch (error) {
    await _writeJson(request.response, HttpStatus.internalServerError, {
      'error': 'Puzzle processing failed: $error',
    });
  }
}

Map<String, Object?>? _dispatchApi(String path, Map<String, Object?> body) =>
    switch (path) {
      '/api/puzzles/slitherlink/generate' => _generatePuzzle(body),
      '/api/puzzles/slitherlink/solve' => _solvePuzzle(body),
      '/api/puzzles/slitherlink/check' => _checkPuzzle(body),
      _ => null,
    };

bool _isLocalDevelopmentOrigin(String origin) {
  final uri = Uri.tryParse(origin);
  return uri != null && (uri.host == 'localhost' || uri.host == '127.0.0.1');
}

Future<Map<String, Object?>> _readJsonObject(HttpRequest request) async {
  final raw = await utf8.decoder.bind(request).join();
  final decoded = jsonDecode(raw);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Request body must be a JSON object.');
  }
  return decoded;
}

Map<String, Object?> _generatePuzzle(Map<String, Object?> body) {
  final rows = _requiredInt(body, 'rows');
  final columns = _requiredInt(body, 'columns');
  if (rows < 1 || columns < 1 || rows * columns > 100) {
    throw const FormatException(
      'Board dimensions must be positive and at most 100 cells.',
    );
  }
  final difficulty = switch (body['difficulty']) {
    'easy' => PuzzleDifficulty.easy,
    'normal' => PuzzleDifficulty.normal,
    'hard' => PuzzleDifficulty.hard,
    null => PuzzleDifficulty.normal,
    _ => throw const FormatException('Unknown difficulty.'),
  };
  final rawClueDensity = body['clueDensity'];
  if (rawClueDensity != null && rawClueDensity is! num) {
    throw const FormatException('Clue density must be a number.');
  }
  final generated = const SlitherlinkGenerator().generate(
    SlitherlinkGenerationOptions(
      rows: rows,
      columns: columns,
      difficulty: difficulty,
      includeBlankCells: body['includeBlankCells'] as bool? ?? true,
      clueDensity: (rawClueDensity as num?)?.toDouble() ?? 0.5,
      includeSolveSteps: false,
    ),
  );
  return {
    'rows': rows,
    'columns': columns,
    'clues': _serializeClues(generated.puzzle.clues),
  };
}

Map<String, Object?> _solvePuzzle(Map<String, Object?> body) {
  final puzzle = _parsePuzzle(body);
  final state = _parseState(body, puzzle.topology);
  final result = const SlitherlinkSolver().solve(puzzle, initialState: state);
  return {
    'solutionCount': result.solutionCount,
    'state': _serializeState(result.state),
    'steps': [
      for (final step in result.steps)
        {
          'ruleId': step.ruleId,
          'highlights': [
            for (final target in step.highlights) _serializeTarget(target),
          ],
          'actions': [
            for (final rawAction in step.actions)
              if (rawAction is SetSlitherlinkEdge)
                {
                  'edge': _serializeEdge(rawAction.edge),
                  'state': rawAction.state.name,
                },
          ],
          'arguments': step.arguments,
        },
    ],
  };
}

Map<String, Object?> _checkPuzzle(Map<String, Object?> body) {
  final puzzle = _parsePuzzle(body);
  final state = _parseState(body, puzzle.topology);
  final result = puzzle.check(state);
  return {'status': result.status.name, 'messageKey': result.messageKey};
}

SlitherlinkPuzzle _parsePuzzle(Map<String, Object?> body) {
  final rows = _requiredInt(body, 'rows');
  final columns = _requiredInt(body, 'columns');
  if (rows < 1 || columns < 1 || rows * columns > 100) {
    throw const FormatException(
      'Board dimensions must be positive and at most 100 cells.',
    );
  }
  final rawClues = body['clues'];
  if (rawClues is! List) {
    throw const FormatException('clues must be an array.');
  }
  final clues = <CellId, int>{};
  for (final raw in rawClues) {
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Each clue must be an object.');
    }
    final row = _requiredInt(raw, 'row');
    final column = _requiredInt(raw, 'column');
    final value = _requiredInt(raw, 'value');
    clues[CellId(row, column)] = value;
  }
  return SlitherlinkPuzzle(
    topology: GridTopology(rows: rows, columns: columns),
    clues: clues,
  );
}

SlitherlinkState _parseState(Map<String, Object?> body, GridTopology topology) {
  final rawEdges = body['edges'] ?? const [];
  if (rawEdges is! List) {
    throw const FormatException('edges must be an array.');
  }
  final edges = <EdgeId, SlitherlinkEdgeState>{};
  for (final raw in rawEdges) {
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Each edge state must be an object.');
    }
    final orientation = switch (raw['orientation']) {
      'horizontal' => EdgeOrientation.horizontal,
      'vertical' => EdgeOrientation.vertical,
      _ => throw const FormatException('Unknown edge orientation.'),
    };
    final edge = orientation == EdgeOrientation.horizontal
        ? EdgeId.horizontal(
            _requiredInt(raw, 'row'),
            _requiredInt(raw, 'column'),
          )
        : EdgeId.vertical(
            _requiredInt(raw, 'row'),
            _requiredInt(raw, 'column'),
          );
    if (!topology.containsEdge(edge)) {
      throw const FormatException('An edge is outside the board.');
    }
    final state = switch (raw['state']) {
      'line' => SlitherlinkEdgeState.line,
      'crossed' => SlitherlinkEdgeState.crossed,
      _ => throw const FormatException('Unknown edge state.'),
    };
    edges[edge] = state;
  }
  return SlitherlinkState(edges);
}

List<Map<String, Object?>> _serializeClues(Map<CellId, int> clues) => [
  for (final entry in clues.entries)
    {'row': entry.key.row, 'column': entry.key.column, 'value': entry.value},
];

List<Map<String, Object?>> _serializeState(SlitherlinkState state) => [
  for (final entry in state.edges.entries)
    {..._serializeEdge(entry.key), 'state': entry.value.name},
];

Map<String, Object?> _serializeEdge(EdgeId edge) => {
  'orientation': edge.orientation.name,
  'row': edge.row,
  'column': edge.column,
};

Map<String, Object?> _serializeTarget(PuzzleTarget target) => switch (target) {
  CellTarget(:final cell) => {
    'type': 'cell',
    'row': cell.row,
    'column': cell.column,
  },
  EdgeTarget(:final edge) => {'type': 'edge', ..._serializeEdge(edge)},
  VertexTarget(:final vertex) => {
    'type': 'vertex',
    'row': vertex.row,
    'column': vertex.column,
  },
};

int _requiredInt(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value is! int) throw FormatException('$key must be an integer.');
  return value;
}

Future<void> _writeJson(
  HttpResponse response,
  int statusCode,
  Map<String, Object?> payload,
) async {
  response
    ..statusCode = statusCode
    ..headers.contentType = ContentType.json;
  response.write(jsonEncode(payload));
  await response.close();
}

ContentType _contentTypeFor(String path) {
  final extension = path.split('.').last.toLowerCase();
  return switch (extension) {
    'css' => ContentType('text', 'css', charset: 'utf-8'),
    'html' => ContentType.html,
    'js' => ContentType('text', 'javascript', charset: 'utf-8'),
    'json' => ContentType.json,
    'svg' => ContentType('image', 'svg+xml'),
    'wasm' => ContentType('application', 'wasm'),
    'woff2' => ContentType('font', 'woff2'),
    'png' => ContentType('image', 'png'),
    _ => ContentType.binary,
  };
}
