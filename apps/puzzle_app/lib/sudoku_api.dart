import 'package:flutter/foundation.dart';
import 'package:puzzle_core/puzzle_core.dart';

final class SudokuApi {
  const SudokuApi();

  Future<SudokuPuzzle> generate({
    required int size,
    required SudokuDifficulty difficulty,
    required double clueDensity,
  }) async {
    final data = await compute(_generateSudoku, {
      'size': size,
      'difficulty': difficulty.name,
      'clueDensity': clueDensity,
    });
    return _puzzleFromData(data);
  }

  Future<SudokuSolveResult> solve(
    SudokuPuzzle puzzle,
    SudokuState state,
  ) async {
    final data = await compute(_solveSudoku, {
      'size': puzzle.size,
      'givens': _valuesToData(puzzle.givens),
      'values': _valuesToData(state.values),
      'notes': [
        for (final entry in state.notes.entries)
          [entry.key.row, entry.key.column, entry.value.toList()..sort()],
      ],
    });
    final finalState = _stateFromData(data['state'] as Map<String, dynamic>);
    final steps = (data['steps'] as List<dynamic>)
        .map((step) => _stepFromData(step as Map<String, dynamic>))
        .toList();
    return SudokuSolveResult(
      state: finalState,
      steps: steps,
      solutionCount: data['solutionCount'] as int,
    );
  }

  SudokuPuzzle _puzzleFromData(Map<String, dynamic> data) => SudokuPuzzle(
    size: data['size'] as int,
    givens: _valuesFromData(data['givens'] as List<dynamic>),
  );

  SudokuState _stateFromData(Map<String, dynamic> data) => SudokuState(
    values: _valuesFromData(data['values'] as List<dynamic>),
    notes: {
      for (final raw in data['notes'] as List<dynamic>)
        CellId(raw[0] as int, raw[1] as int): (raw[2] as List<dynamic>)
            .cast<int>()
            .toSet(),
    },
  );

  SudokuSolveStep _stepFromData(Map<String, dynamic> raw) => SudokuSolveStep(
    ruleId: raw['ruleId'] as String,
    highlights: [
      for (final cell in raw['highlights'] as List<dynamic>)
        CellTarget(CellId(cell[0] as int, cell[1] as int)),
    ],
    actions: [
      for (final action in raw['actions'] as List<dynamic>)
        switch ((action as Map<String, dynamic>)['type']) {
          'value' => SetSudokuValue(
            CellId(action['row'] as int, action['column'] as int),
            action['value'] as int?,
          ),
          'notes' => SetSudokuNotes(
            CellId(action['row'] as int, action['column'] as int),
            (action['values'] as List<dynamic>).cast<int>().toSet(),
          ),
          _ => throw const FormatException('数独推理动作无效。'),
        },
    ],
    arguments: Map<String, Object?>.from(raw['arguments'] as Map),
  );

  List<List<int>> _valuesToData(Map<CellId, int> values) => [
    for (final entry in values.entries)
      [entry.key.row, entry.key.column, entry.value],
  ];

  Map<CellId, int> _valuesFromData(List<dynamic> values) => {
    for (final raw in values)
      CellId(raw[0] as int, raw[1] as int): raw[2] as int,
  };
}

Map<String, dynamic> _generateSudoku(Map<String, Object?> request) {
  final generated = const SudokuGenerator().generate(
    SudokuGenerationOptions(
      size: request['size']! as int,
      difficulty: SudokuDifficulty.values.byName(
        request['difficulty']! as String,
      ),
      clueDensity: request['clueDensity']! as double,
    ),
  );
  return {
    'size': generated.puzzle.size,
    'givens': [
      for (final entry in generated.puzzle.givens.entries)
        [entry.key.row, entry.key.column, entry.value],
    ],
  };
}

Map<String, dynamic> _solveSudoku(Map<String, Object?> request) {
  final size = request['size']! as int;
  Map<CellId, int> valuesFrom(List<dynamic> raw) => {
    for (final item in raw)
      CellId(item[0] as int, item[1] as int): item[2] as int,
  };
  final puzzle = SudokuPuzzle(
    size: size,
    givens: valuesFrom(request['givens']! as List<dynamic>),
  );
  final notes = <CellId, Set<int>>{
    for (final raw in request['notes']! as List<dynamic>)
      CellId(raw[0] as int, raw[1] as int): (raw[2] as List<dynamic>)
          .cast<int>()
          .toSet(),
  };
  final result = const SudokuSolver().solve(
    puzzle,
    initialState: SudokuState(
      values: valuesFrom(request['values']! as List<dynamic>),
      notes: notes,
    ),
  );
  return {
    'solutionCount': result.solutionCount,
    'state': {
      'values': [
        for (final entry in result.state.values.entries)
          [entry.key.row, entry.key.column, entry.value],
      ],
      'notes': [
        for (final entry in result.state.notes.entries)
          [entry.key.row, entry.key.column, entry.value.toList()..sort()],
      ],
    },
    'steps': [
      for (final step in result.steps)
        {
          'ruleId': step.ruleId,
          'highlights': [
            for (final target in step.highlights)
              if (target case CellTarget(:final cell)) [cell.row, cell.column],
          ],
          'actions': [
            for (final action in step.actions)
              switch (action) {
                SetSudokuValue(:final cell, :final value) => {
                  'type': 'value',
                  'row': cell.row,
                  'column': cell.column,
                  'value': value,
                },
                SetSudokuNotes(:final cell, :final values) => {
                  'type': 'notes',
                  'row': cell.row,
                  'column': cell.column,
                  'values': values.toList()..sort(),
                },
              },
          ],
          'arguments': step.arguments,
        },
    ],
  };
}
