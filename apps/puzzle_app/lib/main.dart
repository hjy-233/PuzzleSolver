import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:puzzle_app/slitherlink_page.dart';
import 'package:puzzle_app/sudoku_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BrowserContextMenu.disableContextMenu();
  runApp(const PuzzleApp());
}

class PuzzleApp extends StatelessWidget {
  const PuzzleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PuzzleSolver',
      debugShowCheckedModeBanner: false,
      initialRoute: Uri.base.path == '/sudoku' ? '/sudoku' : '/slitherlink',
      routes: {
        '/slitherlink': (_) => const SlitherlinkPage(),
        '/sudoku': (_) => const SudokuPage(),
      },
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          brightness: Brightness.dark,
          seedColor: const Color(0xFF8EA9FF),
          surface: const Color(0xFF161821),
        ),
        scaffoldBackgroundColor: const Color(0xFF101116),
        cardTheme: const CardThemeData(
          color: Color(0xFF1A1C24),
          elevation: 0,
          margin: EdgeInsets.zero,
        ),
      ),
      home: const SlitherlinkPage(),
    );
  }
}
