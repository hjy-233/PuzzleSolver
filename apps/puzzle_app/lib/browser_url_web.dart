import 'package:web/web.dart' as web;

abstract final class BrowserUrl {
  static void replace(Uri uri) {
    web.window.history.replaceState(null, '', uri.toString());
  }

  static String? readLocalValue(String key) {
    try {
      return web.window.localStorage.getItem(key);
    } on Object {
      return null;
    }
  }

  static void writeLocalValue(String key, String value) {
    try {
      web.window.localStorage.setItem(key, value);
    } on Object {
      // Server-side authorization remains available through the secure cookie.
    }
  }
}
