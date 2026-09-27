import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:puzzle_app/slitherlink_api.dart';
import 'package:puzzle_core/puzzle_core.dart';

void main() {
  test('generates locally with the default Slitherlink controls', () async {
    final puzzle = await const SlitherlinkApi().generate(
      rows: 5,
      columns: 5,
      difficulty: PuzzleDifficulty.normal,
      includeBlankCells: true,
      clueDensity: 0.55,
      useServer: false,
    );

    expect(puzzle.topology.rows, 5);
    expect(puzzle.topology.columns, 5);
    expect(puzzle.clues, isNotEmpty);
  });

  test('solves locally when server access is not enabled', () async {
    final puzzle = SlitherlinkPuzzle(
      topology: const GridTopology(rows: 1, columns: 1),
      clues: {const CellId(0, 0): 4},
    );

    final result = await const SlitherlinkApi().solve(
      puzzle,
      puzzle.initialState,
      useServer: false,
    );

    expect(result.hasUniqueSolution, isTrue);
    expect(puzzle.check(result.state).status, CheckStatus.solved);
  });

  test(
    'server API requests carry an Authorization Bearer invitation',
    () async {
      http.Request? capturedRequest;
      final client = MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          jsonEncode({'rows': 1, 'columns': 1, 'clues': []}),
          200,
        );
      });
      final puzzle = await SlitherlinkApi(client: client).generate(
        rows: 1,
        columns: 1,
        difficulty: PuzzleDifficulty.easy,
        includeBlankCells: false,
        clueDensity: 0.5,
        useServer: true,
        invitationCode: 'test-invitation',
      );

      expect(puzzle.topology.rows, 1);
      expect(
        capturedRequest?.headers['authorization'],
        'Bearer test-invitation',
      );
      client.close();
    },
  );
}
