import 'dart:io';

const rootDirectory = '/srv/puzzle-solver';
const port = 8080;

Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  await for (final request in server) {
    await _serve(request);
  }
}

Future<void> _serve(HttpRequest request) async {
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
