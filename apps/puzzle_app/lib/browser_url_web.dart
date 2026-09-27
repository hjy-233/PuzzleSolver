import 'package:web/web.dart' as web;

abstract final class BrowserUrl {
  static void replace(Uri uri) {
    web.window.history.replaceState(null, '', uri.toString());
  }
}
