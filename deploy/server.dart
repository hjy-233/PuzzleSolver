import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:puzzle_core/puzzle_core.dart';

import 'access_control.dart';

const rootDirectory = String.fromEnvironment(
  'PUZZLE_WEB_ROOT',
  defaultValue: '/srv/puzzle-solver',
);
const port = int.fromEnvironment('PUZZLE_PORT', defaultValue: 8080);
const _maximumRequestBytes = 64 * 1024;
const _maximumActiveApiRequests = 4;
const _maximumHeavyOperations = 1;
const _maximumRateLimitKeys = 4096;
const _accessControlDataDirectory = String.fromEnvironment(
  'PUZZLE_DATA_DIR',
  defaultValue: '/app/data',
);

final _apiRateLimiter = _ApiRateLimiter();
late final AccessControlStore _accessControlStore;
late final String _webBuildVersion;
var _activeApiRequests = 0;
var _activeHeavyOperations = 0;

Future<void> main() async {
  final mainJsFile = File('$rootDirectory/main.dart.js');
  if (!await mainJsFile.exists()) {
    throw StateError('Flutter web entrypoint not found: ${mainJsFile.path}');
  }
  final mainJsStat = await mainJsFile.stat();
  _webBuildVersion =
      '${mainJsStat.modified.microsecondsSinceEpoch}-${mainJsStat.size}';

  _accessControlStore = await AccessControlStore.open(
    dataDirectory: Directory(_accessControlDataDirectory),
  );
  stdout.writeln(
    'Permanent PuzzleSolver API Bearer code: '
    '${_accessControlStore.currentInvitationCode}',
  );
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
    'no-store, no-cache, max-age=0, must-revalidate',
  );
  request.response.headers.set('Referrer-Policy', 'no-referrer');
  if (request.method == 'HEAD') {
    await request.response.close();
    return;
  }

  if (file.path.endsWith('/index.html')) {
    final html = await file.readAsString();
    request.response.write(
      html.replaceFirst(
        'src="flutter_bootstrap.js"',
        'src="flutter_bootstrap.js?v=$_webBuildVersion"',
      ),
    );
    await request.response.close();
    return;
  }
  if (file.path.endsWith('/flutter_bootstrap.js')) {
    final bootstrap = await file.readAsString();
    const entrypoint = '"mainJsPath":"main.dart.js"';
    if (!bootstrap.contains(entrypoint)) {
      throw StateError('Could not version Flutter web entrypoint URL.');
    }
    request.response.write(
      bootstrap.replaceFirst(
        entrypoint,
        '"mainJsPath":"main.dart.js?v=$_webBuildVersion"',
      ),
    );
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
      'Content-Type, Authorization',
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

  final clientAddress = _clientAddress(request);
  final isHeavyOperation = _isHeavyOperation(request.uri.path);
  final requestLimit = switch (request.uri.path) {
    '/api/puzzles/slitherlink/generate' => 4,
    '/api/puzzles/slitherlink/solve' => 4,
    '/api/puzzles/slitherlink/check' => 120,
    _ => 30,
  };
  final retryAfter = _apiRateLimiter.retryAfter(
    clientAddress,
    request.uri.path,
    requestLimit,
  );
  if (retryAfter != null) {
    request.response.headers.set(HttpHeaders.retryAfterHeader, '$retryAfter');
    await _writeJson(request.response, HttpStatus.tooManyRequests, {
      'code': 'rate_limited',
      'error': 'Too many requests. Please retry later.',
    });
    return;
  }
  final bearerToken = _bearerToken(request);
  if (!_accessControlStore.isInvitationValid(bearerToken)) {
    await _writeJson(request.response, HttpStatus.unauthorized, {
      'code': 'invalid_invitation',
      'error': 'A valid Bearer invitation code is required.',
    });
    return;
  }
  if (_activeApiRequests >= _maximumActiveApiRequests) {
    request.response.headers.set(HttpHeaders.retryAfterHeader, '2');
    await _writeJson(request.response, HttpStatus.serviceUnavailable, {
      'code': 'server_busy',
      'error': 'The server is busy. Please retry shortly.',
    });
    return;
  }
  if (isHeavyOperation && _activeHeavyOperations >= _maximumHeavyOperations) {
    request.response.headers.set(HttpHeaders.retryAfterHeader, '5');
    await _writeJson(request.response, HttpStatus.serviceUnavailable, {
      'code': 'server_busy',
      'error': 'A puzzle operation is already running. Please retry shortly.',
    });
    return;
  }

  _activeApiRequests++;
  if (isHeavyOperation) _activeHeavyOperations++;
  try {
    final body = await _readJsonObject(request);
    final path = request.uri.path;
    if (_isHeavyOperation(path)) {
      _validateHeavyOperation(path, body);
      final allowed = await _accessControlStore.consumeHeavyOperation(
        clientAddress,
        invited: true,
      );
      if (!allowed) {
        await _writeJson(request.response, HttpStatus.tooManyRequests, {
          'code': 'daily_quota_exceeded',
          'error': 'The daily server allowance is used. Continue locally.',
        });
        return;
      }
    }
    final payload = await Isolate.run(() => _dispatchApi(path, body));
    if (payload == null) {
      await _writeJson(request.response, HttpStatus.notFound, {
        'error': 'Unknown API endpoint.',
      });
      return;
    }
    await _writeJson(request.response, HttpStatus.ok, payload);
  } on _PayloadTooLarge {
    await _writeJson(request.response, 413, {
      'error': 'Request body must not exceed 64 KiB.',
    });
  } on TimeoutException {
    await _writeJson(request.response, HttpStatus.requestTimeout, {
      'error': 'Request body was not received in time.',
    });
  } on FormatException catch (error) {
    await _writeJson(request.response, HttpStatus.badRequest, {
      'error': error.message,
    });
  } on ArgumentError catch (error) {
    await _writeJson(request.response, HttpStatus.badRequest, {
      'error': error.message ?? 'Invalid request.',
    });
  } on StateError catch (error) {
    if (request.uri.path == '/api/puzzles/slitherlink/generate' &&
        _isGenerationConvergenceError(error)) {
      await _writeJson(request.response, HttpStatus.serviceUnavailable, {
        'code': 'generation_failed',
        'error': 'Server generation did not converge; continuing locally.',
      });
      return;
    }
    await _writeJson(request.response, HttpStatus.unprocessableEntity, {
      'error': error.message,
    });
  } catch (error) {
    if (request.uri.path == '/api/puzzles/slitherlink/generate' &&
        _isGenerationConvergenceError(error)) {
      await _writeJson(request.response, HttpStatus.serviceUnavailable, {
        'code': 'generation_failed',
        'error': 'Server generation did not converge; continuing locally.',
      });
      return;
    }
    await _writeJson(request.response, HttpStatus.internalServerError, {
      'error': 'Puzzle processing failed: $error',
    });
  } finally {
    _activeApiRequests--;
    if (isHeavyOperation) _activeHeavyOperations--;
  }
}

bool _isGenerationConvergenceError(Object error) => error.toString().contains(
  'Could not generate a unique irregular Slitherlink puzzle.',
);

bool _isHeavyOperation(String path) =>
    path == '/api/puzzles/slitherlink/generate' ||
    path == '/api/puzzles/slitherlink/solve';

void _validateHeavyOperation(String path, Map<String, Object?> body) {
  if (path == '/api/puzzles/slitherlink/solve') {
    final puzzle = _parsePuzzle(body);
    _parseState(body, puzzle.topology);
    return;
  }
  final rows = _requiredInt(body, 'rows');
  final columns = _requiredInt(body, 'columns');
  if (rows < 1 ||
      columns < 1 ||
      rows > 100 ||
      columns > 100 ||
      rows * columns > 100) {
    throw const FormatException(
      'Board dimensions must be positive and at most 100 cells.',
    );
  }
  final difficulty = body['difficulty'];
  if (difficulty != null &&
      (difficulty is! String ||
          !{'easy', 'normal', 'hard'}.contains(difficulty))) {
    throw const FormatException('Unknown difficulty.');
  }
  final includeBlankCells = body['includeBlankCells'];
  if (includeBlankCells != null && includeBlankCells is! bool) {
    throw const FormatException('includeBlankCells must be a boolean.');
  }
  final density = body['clueDensity'];
  if (density != null &&
      (density is! num || !density.isFinite || density < 0 || density > 1)) {
    throw const FormatException('Clue density must be between 0 and 1.');
  }
}

String? _bearerToken(HttpRequest request) {
  final authorization = request.headers.value(HttpHeaders.authorizationHeader);
  if (authorization == null) return null;
  final separator = authorization.indexOf(' ');
  if (separator < 0 ||
      authorization.substring(0, separator).toLowerCase() != 'bearer') {
    return null;
  }
  final token = authorization.substring(separator + 1).trim();
  return token.isEmpty ? null : token;
}

String _clientAddress(HttpRequest request) {
  final forwardedAddress = request.headers.value('cf-connecting-ip')?.trim();
  final parsedForwardedAddress = forwardedAddress == null
      ? null
      : InternetAddress.tryParse(forwardedAddress);
  if (parsedForwardedAddress != null) {
    return parsedForwardedAddress.address;
  }
  return request.connectionInfo?.remoteAddress.address ?? 'unknown';
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
  if (request.contentLength > _maximumRequestBytes) {
    throw const _PayloadTooLarge();
  }
  final bytes = BytesBuilder(copy: false);
  await request
      .fold<void>(null, (previous, chunk) {
        if (bytes.length + chunk.length > _maximumRequestBytes) {
          throw const _PayloadTooLarge();
        }
        bytes.add(chunk);
      })
      .timeout(const Duration(seconds: 5));
  final raw = utf8.decode(bytes.takeBytes());
  final decoded = jsonDecode(raw);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Request body must be a JSON object.');
  }
  return decoded;
}

Map<String, Object?> _generatePuzzle(Map<String, Object?> body) {
  final rows = _requiredInt(body, 'rows');
  final columns = _requiredInt(body, 'columns');
  if (rows < 1 ||
      columns < 1 ||
      rows > 100 ||
      columns > 100 ||
      rows * columns > 100) {
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
  late final GeneratedSlitherlinkPuzzle generated;
  while (true) {
    try {
      generated = const SlitherlinkGenerator().generate(
        SlitherlinkGenerationOptions(
          rows: rows,
          columns: columns,
          difficulty: difficulty,
          includeBlankCells: body['includeBlankCells'] as bool? ?? true,
          clueDensity: (rawClueDensity as num?)?.toDouble() ?? 0.55,
          includeSolveSteps: false,
        ),
      );
      break;
    } on StateError catch (error) {
      if (!error.message.contains(
        'Could not generate a unique irregular Slitherlink puzzle.',
      )) {
        rethrow;
      }
    }
  }
  return {
    'rows': rows,
    'columns': columns,
    'clues': _serializeClues(generated.puzzle.clues),
  };
}

Map<String, Object?> _solvePuzzle(Map<String, Object?> body) {
  final puzzle = _parsePuzzle(body);
  final state = _parseState(body, puzzle.topology);
  final area = puzzle.topology.rows * puzzle.topology.columns;
  final maxSearchNodes = area <= 25
      ? 20000
      : area <= 64
      ? 8000
      : 2500;
  final result = SlitherlinkSolver(
    maxSearchNodes: maxSearchNodes,
  ).solve(puzzle, initialState: state);
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
  if (rows < 1 ||
      columns < 1 ||
      rows > 100 ||
      columns > 100 ||
      rows * columns > 100) {
    throw const FormatException(
      'Board dimensions must be positive and at most 100 cells.',
    );
  }
  final rawClues = body['clues'];
  if (rawClues is! List) {
    throw const FormatException('clues must be an array.');
  }
  if (rawClues.length > rows * columns) {
    throw const FormatException(
      'clues contains more entries than board cells.',
    );
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
  if (rawEdges.length > topology.allEdges.length) {
    throw const FormatException(
      'edges contains more entries than board edges.',
    );
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

final class _ApiRateLimiter {
  final Map<String, _RateWindow> _windows = {};

  int? retryAfter(String clientAddress, String path, int limit) {
    final now = DateTime.now();
    if (_windows.length >= _maximumRateLimitKeys) {
      _windows.removeWhere(
        (_, window) =>
            now.difference(window.startedAt) >= const Duration(minutes: 1),
      );
    }
    final routeKey = switch (path) {
      '/api/puzzles/slitherlink/generate' => 'generate',
      '/api/puzzles/slitherlink/solve' => 'solve',
      '/api/puzzles/slitherlink/check' => 'check',
      _ => 'other',
    };
    final key = '$clientAddress:$routeKey';
    var window = _windows[key];
    if (window == null) {
      if (_windows.length >= _maximumRateLimitKeys) return 60;
      window = _RateWindow(now);
      _windows[key] = window;
    } else if (now.difference(window.startedAt) >= const Duration(minutes: 1)) {
      window
        ..startedAt = now
        ..count = 0;
    }
    if (window.count >= limit) {
      final remainingSeconds = 60 - now.difference(window.startedAt).inSeconds;
      return remainingSeconds < 1 ? 1 : remainingSeconds;
    }
    window.count++;
    return null;
  }
}

final class _RateWindow {
  _RateWindow(this.startedAt);

  DateTime startedAt;
  int count = 0;
}

final class _PayloadTooLarge implements Exception {
  const _PayloadTooLarge();
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
