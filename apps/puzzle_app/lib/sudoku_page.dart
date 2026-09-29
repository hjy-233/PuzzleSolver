import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:puzzle_core/puzzle_core.dart';

import 'browser_url.dart';
import 'puzzle_share.dart';
import 'puzzle_widgets.dart';
import 'sudoku_api.dart';

class SudokuPage extends StatefulWidget {
  const SudokuPage({super.key});

  @override
  State<SudokuPage> createState() => _SudokuPageState();
}

class _SudokuPageState extends State<SudokuPage> {
  static const _api = SudokuApi();
  final _focusNode = FocusNode();
  final _boardController = PuzzleBoardController();
  late SudokuPuzzle _puzzle;
  late PuzzleSession<SudokuState, SudokuAction> _session;
  List<SudokuSolveStep> _steps = [];
  SudokuState? _stepBaseState;
  final Set<CellId> _scopeHighlights = {};
  final Set<CellId> _evidenceHighlights = {};
  final Set<CellId> _changeHighlights = {};
  CellId? _selectedCell;
  Timer? _highlightTimer;
  int? _selectedStepIndex;
  int _size = 9;
  SudokuDifficulty _difficulty = SudokuDifficulty.medium;
  double _clueDensity = .42;
  bool _noteMode = false;
  bool _editingClues = false;
  bool _isBusy = false;
  bool _stepsVisible = true;
  bool _puzzleSidebarVisible = true;
  bool _controlsSidebarVisible = true;
  bool _completionDialogOpen = false;
  bool _completionDialogDismissed = false;
  String _status = '点击格子选择，输入数字；候选模式可记录笔记。';

  @override
  void initState() {
    super.initState();
    final query = Map<String, String>.from(Uri.base.queryParameters)
      ..remove('code');
    final canonical = Uri.base.replace(
      path: '/sudoku',
      queryParameters: query.isEmpty ? null : query,
    );
    if (canonical.toString() != Uri.base.toString()) {
      BrowserUrl.replace(canonical);
    }
    final encodedPuzzle = Uri.base.queryParameters['p'];
    if (encodedPuzzle != null) {
      try {
        _puzzle = SudokuShare.decodePuzzle(encodedPuzzle);
        _size = _puzzle.size;
        _session = PuzzleSession.start(
          initialState: _puzzle.initialState,
          reducer: _puzzle.reduce,
        );
        final encodedProgress = Uri.base.queryParameters['s'];
        if (encodedProgress != null) {
          _restoreProgress(
            SudokuShare.decodeProgress(encodedProgress, _puzzle),
          );
          _status = '已从分享链接恢复题目和进度。';
        } else {
          _status = '已从分享链接打开题目。';
        }
        return;
      } on FormatException catch (error) {
        _status = '分享链接无效：${error.message}';
      }
    }
    _puzzle = SudokuPuzzle(size: _size, givens: const {});
    _session = PuzzleSession.start(
      initialState: _puzzle.initialState,
      reducer: _puzzle.reduce,
    );
    unawaited(_newPuzzle());
  }

  void _restoreProgress(SudokuState state) {
    for (final entry in state.values.entries) {
      if (!_puzzle.givens.containsKey(entry.key)) {
        _session = _session.apply(SetSudokuValue(entry.key, entry.value));
      }
    }
    for (final entry in state.notes.entries) {
      _session = _session.apply(SetSudokuNotes(entry.key, entry.value));
    }
  }

  Future<void> _newPuzzle() async {
    _cancelHighlight();
    setState(() {
      _isBusy = true;
      _status = '正在浏览器本地生成数独…';
    });
    try {
      final puzzle = await _api.generate(
        size: _size,
        difficulty: _difficulty,
        clueDensity: _clueDensity,
      );
      if (!mounted) return;
      setState(() {
        _puzzle = puzzle;
        _session = PuzzleSession.start(
          initialState: puzzle.initialState,
          reducer: puzzle.reduce,
        );
        _steps = [];
        _stepBaseState = null;
        _selectedCell = null;
        _selectedStepIndex = null;
        _editingClues = false;
        _isBusy = false;
        _status = '新题已生成，保证唯一解。';
      });
      _syncUrl();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _status = '题目生成失败：$error';
      });
    }
  }

  void _startEntry() {
    setState(() {
      _puzzle = SudokuPuzzle(size: _size, givens: const {});
      _session = PuzzleSession.start(
        initialState: _puzzle.initialState,
        reducer: _puzzle.reduce,
      );
      _steps = [];
      _stepBaseState = null;
      _selectedCell = null;
      _selectedStepIndex = null;
      _editingClues = true;
      _status = '点选格子后输入题目给定数字；录入完成后结束录入。';
    });
    _syncUrl();
  }

  void _finishEntry() {
    setState(() {
      _editingClues = false;
      _status = _puzzle.givens.isEmpty
          ? '题目还没有数字。'
          : '已录入 ${_puzzle.givens.length} 个数字，可以开始求解。';
    });
  }

  void _selectCell(CellId cell) {
    setState(() {
      _selectedCell = cell;
      _status = _puzzle.givens.containsKey(cell)
          ? '这是题目给定数字。'
          : _editingClues
          ? '选择数字录入题目；再次点击已录入数字可清除。'
          : '已选中格子，点击数字输入。';
    });
  }

  void _inputValue(int value) {
    final cell = _selectedCell;
    if (cell == null) {
      setState(() => _status = '请先选择一个格子。');
      return;
    }
    if (_editingClues) {
      final givens = Map<CellId, int>.from(_puzzle.givens);
      if (givens[cell] == value) {
        givens.remove(cell);
      } else {
        givens[cell] = value;
      }
      final next = SudokuPuzzle(size: _size, givens: givens);
      _cancelHighlight();
      setState(() {
        _puzzle = next;
        _session = PuzzleSession.start(
          initialState: next.initialState,
          reducer: next.reduce,
        );
        _steps = [];
        _stepBaseState = null;
        _status = '题目数字已更新。';
      });
      _syncUrl();
      return;
    }
    if (_puzzle.givens.containsKey(cell)) {
      setState(() => _status = '题目给定数字不能修改。');
      return;
    }
    final current = _session.state;
    if (_noteMode) {
      final notes = {...current.notesAt(cell)};
      if (!notes.add(value)) notes.remove(value);
      _apply(SetSudokuNotes(cell, notes), checkCompletion: false);
      return;
    }
    _apply(SetSudokuValue(cell, value));
  }

  void _erase() {
    final cell = _selectedCell;
    if (cell == null) return;
    if (_editingClues) {
      final givens = Map<CellId, int>.from(_puzzle.givens)..remove(cell);
      final next = SudokuPuzzle(size: _size, givens: givens);
      setState(() {
        _puzzle = next;
        _session = PuzzleSession.start(
          initialState: next.initialState,
          reducer: next.reduce,
        );
        _status = '题目数字已删除。';
      });
      _syncUrl();
      return;
    }
    _apply(SetSudokuValue(cell, null));
  }

  void _apply(SudokuAction action, {bool checkCompletion = true}) {
    _cancelHighlight();
    setState(() {
      _session = _session.apply(action);
      _steps = [];
      _stepBaseState = null;
      _selectedStepIndex = null;
      _clearHighlights();
      _status = action is SetSudokuNotes ? '候选笔记已更新。' : '数字已更新。';
      if (action is SetSudokuValue && checkCompletion) {
        _changeHighlights.addAll(_conflictingCells());
        _status = switch (_puzzle.check(_session.state).status) {
          CheckStatus.invalid => '当前填法有冲突；高亮数字可帮助定位。',
          CheckStatus.solved => '数独完成！',
          CheckStatus.incomplete => '数字已更新。',
        };
      }
    });
    _syncUrl();
    if (checkCompletion && action is SetSudokuValue) {
      unawaited(_showCompletionIfSolved());
    }
  }

  Future<void> _hint() async {
    if (_puzzle.givens.isEmpty) {
      setState(() => _status = '先录入一道数独题。');
      return;
    }
    setState(() {
      _isBusy = true;
      _status = '正在寻找下一步推理…';
    });
    try {
      final result = await _api.solve(_puzzle, _session.state);
      if (!mounted) return;
      if (!result.hasUniqueSolution || result.steps.isEmpty) {
        setState(() {
          _isBusy = false;
          _status = result.solutionCount == 0
              ? '当前填写与题目冲突，无法继续推理。'
              : '没有可应用的提示步骤。';
        });
        return;
      }
      _applyStep(result.steps.first);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _status = '提示失败：$error';
      });
    }
  }

  Future<void> _solve() async {
    if (_puzzle.givens.isEmpty) {
      setState(() => _status = '先录入一道数独题。');
      return;
    }
    setState(() {
      _isBusy = true;
      _status = '正在浏览器本地自动解题…';
    });
    try {
      final result = await _api.solve(_puzzle, _session.state);
      if (!mounted) return;
      if (!result.hasUniqueSolution) {
        setState(() {
          _isBusy = false;
          _status = result.solutionCount == 0
              ? '当前题目没有解。'
              : '当前题目有多个解，无法确定唯一答案。';
        });
        return;
      }
      final baseState = _steps.isEmpty ? _session.state : _stepBaseState;
      setState(() {
        _stepBaseState ??= baseState;
        for (final step in result.steps) {
          for (final action in step.actions) {
            _session = _session.apply(action);
          }
        }
        _steps = [..._steps, ...result.steps];
        if (_steps.isNotEmpty) {
          _selectedStepIndex = _steps.length - 1;
          _setStepHighlights(_steps.last);
        }
        _isBusy = false;
        _status = '已完成求解，共 ${result.steps.length} 个推理步骤。';
      });
      _syncUrl();
      unawaited(_showCompletionIfSolved());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _status = '自动解题失败：$error';
      });
    }
  }

  void _applyStep(SudokuSolveStep step) {
    final baseState = _steps.isEmpty ? _session.state : null;
    _cancelHighlight();
    setState(() {
      _stepBaseState ??= baseState;
      for (final action in step.actions) {
        _session = _session.apply(action);
      }
      _steps = [..._steps, step];
      _selectedStepIndex = _steps.length - 1;
      _setStepHighlights(step);
      _isBusy = false;
      _status = _explanation(step);
    });
    _syncUrl();
    unawaited(_showCompletionIfSolved());
    _highlightTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(_clearHighlights);
    });
  }

  Future<void> _check() async {
    final result = _puzzle.check(_session.state);
    setState(() {
      _status = switch (result.status) {
        CheckStatus.solved => '完成：每行、每列和每宫均符合规则。',
        CheckStatus.invalid => '当前有重复数字，请检查高亮冲突。',
        CheckStatus.incomplete => '还没有完成，可以继续填写或使用提示。',
      };
      _clearHighlights();
      _changeHighlights.addAll(_conflictingCells());
    });
    if (result.status == CheckStatus.solved) {
      unawaited(_showCompletionIfSolved());
    }
    if (_changeHighlights.isNotEmpty) {
      _highlightTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) setState(_clearHighlights);
      });
    }
  }

  Set<CellId> _conflictingCells() {
    final conflicts = <CellId>{};
    for (final unit in _puzzle.units) {
      final cellsByValue = <int, List<CellId>>{};
      for (final cell in unit) {
        final value = _session.state.valueAt(cell);
        if (value != null) cellsByValue.putIfAbsent(value, () => []).add(cell);
      }
      for (final cells in cellsByValue.values) {
        if (cells.length > 1) conflicts.addAll(cells);
      }
    }
    return conflicts;
  }

  Future<void> _showCompletionIfSolved() async {
    if (_puzzle.check(_session.state).status != CheckStatus.solved) {
      _completionDialogDismissed = false;
      return;
    }
    if (_completionDialogOpen || _completionDialogDismissed) return;
    _completionDialogOpen = true;
    final newPuzzle = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('数独完成！'),
        content: const Text('恭喜，你完成了这道数独。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('新题'),
          ),
        ],
      ),
    );
    _completionDialogOpen = false;
    if (!mounted) return;
    if (newPuzzle == true) {
      _completionDialogDismissed = false;
      unawaited(_newPuzzle());
    } else {
      _completionDialogDismissed = true;
    }
  }

  void _undo() {
    if (!_session.canUndo) return;
    setState(() {
      _session = _session.undo();
      _steps = [];
      _stepBaseState = null;
      _selectedStepIndex = null;
      _clearHighlights();
      _status = '已撤销一步。';
    });
    _syncUrl();
  }

  void _redo() {
    if (!_session.canRedo) return;
    setState(() {
      _session = _session.redo();
      _steps = [];
      _stepBaseState = null;
      _selectedStepIndex = null;
      _status = '已重做一步。';
    });
    _syncUrl();
    unawaited(_showCompletionIfSolved());
  }

  void _replayToStep(int index) {
    final base = _stepBaseState ?? _puzzle.initialState;
    _session = PuzzleSession.start(
      initialState: _puzzle.initialState,
      reducer: _puzzle.reduce,
    );
    for (final entry in base.values.entries) {
      if (!_puzzle.givens.containsKey(entry.key)) {
        _session = _session.apply(SetSudokuValue(entry.key, entry.value));
      }
    }
    for (final entry in base.notes.entries) {
      _session = _session.apply(SetSudokuNotes(entry.key, entry.value));
    }
    for (final action
        in _steps.take(index + 1).expand((step) => step.actions)) {
      _session = _session.apply(action);
    }
    _cancelHighlight();
    setState(() {
      _selectedStepIndex = index;
      _setStepHighlights(_steps[index]);
      _status = _explanation(_steps[index]);
    });
    _syncUrl();
    _highlightTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(_clearHighlights);
    });
  }

  void _clearHighlights() {
    _scopeHighlights.clear();
    _evidenceHighlights.clear();
    _changeHighlights.clear();
  }

  void _setStepHighlights(SudokuSolveStep step) {
    _clearHighlights();
    _scopeHighlights.addAll(_cellsArgument(step, 'scope'));
    _evidenceHighlights.addAll(_cellsArgument(step, 'evidence'));
    _changeHighlights.addAll(_cellsArgument(step, 'changes'));
    _changeHighlights.addAll(
      step.actions.map(
        (action) => switch (action) {
          SetSudokuValue(:final cell) => cell,
          SetSudokuNotes(:final cell) => cell,
        },
      ),
    );
  }

  Set<CellId> _cellsArgument(SudokuSolveStep step, String key) {
    final raw = step.arguments[key];
    if (raw is! List) return {};
    return {
      for (final item in raw)
        if (item is List &&
            item.length == 2 &&
            item[0] is int &&
            item[1] is int)
          CellId(item[0] as int, item[1] as int),
    };
  }

  String _explanation(SudokuSolveStep step) {
    final value = step.arguments['value'];
    final removedCandidates = step.arguments['removed'] as int? ?? 0;
    final filled = step.actions.whereType<SetSudokuValue>().length;
    final changes = [
      if (filled > 0) '填入 $filled 格',
      if (removedCandidates > 0) '排除 $removedCandidates 个候选',
    ].join(' · ');
    return switch (step.ruleId) {
      'sudoku.nakedSingle' => '高亮格所在的行、列和宫已经排除了其他数字，只能填 $value。$changes',
      'sudoku.hiddenSingle' =>
        '高亮${step.arguments['unit'] ?? '区域'}中，其他空格都被橙色依据排除了 $value，因此蓝色格必须填 $value。$changes',
      'sudoku.pair' =>
        '两个橙色格被同一对候选 ${step.arguments['pair']} 锁定，蓝色格可排除这两个候选。$changes',
      'sudoku.boxLine' => '橙色候选在宫与行或列的交叠处被锁定，因此蓝色格不能再使用 $value。$changes',
      'sudoku.contradictionElimination' =>
        '若蓝色格填 $value，继续推理会产生冲突，因此排除该候选。$changes',
      'sudoku.contradictionSearch' => '逐一验证其他候选都会产生冲突，因此蓝色格只能填 $value。$changes',
      _ => changes,
    };
  }

  String _stepTitle(SudokuSolveStep step) => switch (step.ruleId) {
    'sudoku.nakedSingle' => '唯一候选',
    'sudoku.hiddenSingle' => '区域唯一位置',
    'sudoku.pair' => 'Pair',
    'sudoku.boxLine' => 'Box-Line',
    'sudoku.contradictionElimination' || 'sudoku.contradictionSearch' => '矛盾排除',
    _ => '推理',
  };

  void _syncUrl() {
    BrowserUrl.replace(
      Uri.base.replace(
        path: '/sudoku',
        queryParameters: {
          'p': SudokuShare.encodePuzzle(_puzzle),
          's': SudokuShare.encodeProgress(_session.state),
        },
      ),
    );
  }

  Future<void> _share(_ShareMode mode) async {
    final url = Uri.base
        .replace(
          path: '/sudoku',
          queryParameters: {
            if (mode != _ShareMode.pageOnly)
              'p': SudokuShare.encodePuzzle(_puzzle),
            if (mode == _ShareMode.withProgress)
              's': SudokuShare.encodeProgress(_session.state),
          },
        )
        .toString();
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('数独分享链接已复制。')));
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final number = int.tryParse(key.keyLabel);
    if (number != null && number >= 1 && number <= _size) {
      _inputValue(number);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace ||
        key == LogicalKeyboardKey.delete) {
      _erase();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyN && !_editingClues) {
      setState(() => _noteMode = !_noteMode);
      return KeyEventResult.handled;
    }
    final pan = switch (key) {
      LogicalKeyboardKey.arrowLeft => const Offset(48, 0),
      LogicalKeyboardKey.arrowRight => const Offset(-48, 0),
      LogicalKeyboardKey.arrowUp => const Offset(0, 48),
      LogicalKeyboardKey.arrowDown => const Offset(0, -48),
      _ => null,
    };
    if (pan != null) {
      _boardController.panBy(pan);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _cancelHighlight() {
    _highlightTimer?.cancel();
    _highlightTimer = null;
  }

  void _zoomBoard(double scale) {
    _boardController.zoomCentered(MediaQuery.sizeOf(context), scale);
  }

  void _showSettings() {
    showPuzzleSettingsSheet(
      context,
      (sheetContext, refresh) => _controlsPanel(
        settingsOnly: true,
        refreshSettings: refresh,
        onClose: () => Navigator.pop(sheetContext),
      ),
    );
  }

  @override
  void dispose() {
    _cancelHighlight();
    _focusNode.dispose();
    _boardController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final mobile = width < 920;
    final board = _SudokuBoard(
      puzzle: _puzzle,
      state: _session.state,
      selected: _selectedCell,
      scopeHighlights: _scopeHighlights,
      evidenceHighlights: _evidenceHighlights,
      changeHighlights: _changeHighlights,
      onSelect: _selectCell,
      boardController: _boardController,
      onZoom: _zoomBoard,
      showPuzzleSidebarButton: !mobile && !_puzzleSidebarVisible,
      showControlsSidebarButton: !mobile && !_controlsSidebarVisible,
      onShowPuzzleSidebar: () => setState(() => _puzzleSidebarVisible = true),
      onShowControlsSidebar: () =>
          setState(() => _controlsSidebarVisible = true),
    );
    return Scaffold(
      drawer: mobile ? _mobileDrawer(context) : null,
      appBar: PuzzleTopBar(
        mobile: mobile,
        width: width,
        puzzleName: '数独',
        canUndo: _session.canUndo,
        canRedo: _session.canRedo,
        onShare: (choice) => unawaited(
          _share(switch (choice) {
            PuzzleShareChoice.page => _ShareMode.pageOnly,
            PuzzleShareChoice.puzzle => _ShareMode.puzzleOnly,
            PuzzleShareChoice.progress => _ShareMode.withProgress,
          }),
        ),
        onNewPuzzle: _isBusy ? null : () => unawaited(_newPuzzle()),
        onUndo: _undo,
        onRedo: _redo,
      ),
      body: Focus(
        autofocus: true,
        focusNode: _focusNode,
        onKeyEvent: _onKey,
        child: PuzzleWorkspace(
          board: board,
          leftSidebar: _desktopPuzzlePanel(),
          rightSidebar: _controlsPanel(),
          mobileControls: _numberPad(),
          mobileSteps: _mobileSteps(),
          showLeftSidebar: _puzzleSidebarVisible,
          showRightSidebar: _controlsSidebarVisible,
          showMobileSteps: _stepsVisible,
          onShowMobileSteps: () => setState(() => _stepsVisible = true),
        ),
      ),
    );
  }

  Widget _mobileDrawer(BuildContext context) => Drawer(
    child: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(padding: EdgeInsets.all(20), child: Text('谜题库')),
          ListTile(
            leading: const Icon(Icons.grid_3x3),
            title: const Text('数独'),
            selected: true,
            subtitle: Text('$_size × $_size'),
            onTap: () => Navigator.pop(context),
          ),
          ListTile(
            leading: const Icon(Icons.route_outlined),
            title: const Text('数回'),
            onTap: () =>
                Navigator.pushReplacementNamed(context, '/slitherlink'),
          ),
        ],
      ),
    ),
  );

  List<PuzzleStepItem> get _presentedSteps => [
    for (final step in _steps)
      PuzzleStepItem(title: _stepTitle(step), description: _explanation(step)),
  ];

  Widget _desktopPuzzlePanel() => PuzzleLibrarySidebar(
    puzzleName: '数独',
    puzzleIcon: Icons.grid_3x3,
    sizeLabel: '$_size × $_size',
    otherPuzzleName: '数回',
    otherPuzzleIcon: Icons.route_outlined,
    onSelectOtherPuzzle: () =>
        Navigator.pushReplacementNamed(context, '/slitherlink'),
    steps: _presentedSteps,
    selectedStepIndex: _selectedStepIndex,
    onStepTap: _replayToStep,
    onClose: () => setState(() => _puzzleSidebarVisible = false),
  );

  Widget _mobileSteps() => PuzzleMobileStepsPanel(
    steps: _presentedSteps,
    selectedStepIndex: _selectedStepIndex,
    onStepTap: _replayToStep,
    onHide: () => setState(() => _stepsVisible = false),
    status: _status,
  );

  Widget _numberPad() => Material(
    color: const Color(0xFF161821),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            TextButton.icon(
              onPressed: _editingClues
                  ? null
                  : () => setState(() => _noteMode = !_noteMode),
              icon: Icon(_noteMode ? Icons.edit_note : Icons.notes),
              label: Text(_noteMode ? '候选模式' : '候选笔记'),
            ),
            TextButton.icon(
              onPressed: _editingClues ? _finishEntry : _startEntry,
              icon: Icon(_editingClues ? Icons.check : Icons.edit_note),
              label: Text(_editingClues ? '完成录入' : '录入题目'),
            ),
          ],
        ),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 4,
          children: [
            for (var value = 1; value <= _size; value++)
              SizedBox(
                width: 44,
                child: TextButton(
                  onPressed: _isBusy ? null : () => _inputValue(value),
                  child: Text('$value', style: const TextStyle(fontSize: 19)),
                ),
              ),
            IconButton(
              tooltip: '擦除',
              onPressed: _erase,
              icon: const Icon(Icons.backspace_outlined),
            ),
          ],
        ),
        PuzzleMobileActionBar(
          actions: [
            PuzzleActionItem(
              icon: Icons.lightbulb_outline,
              label: '提示',
              onPressed: _isBusy || _editingClues
                  ? null
                  : () => unawaited(_hint()),
            ),
            PuzzleActionItem(
              icon: Icons.auto_fix_high,
              label: '自动解题',
              onPressed: _isBusy || _editingClues
                  ? null
                  : () => unawaited(_solve()),
            ),
            PuzzleActionItem(
              icon: Icons.fact_check_outlined,
              label: '检查',
              onPressed: _editingClues ? null : _check,
            ),
            PuzzleActionItem(
              icon: Icons.more_horiz,
              label: '设置',
              onPressed: _showSettings,
            ),
          ],
        ),
      ],
    ),
  );

  Widget _controlsPanel({
    bool settingsOnly = false,
    VoidCallback? refreshSettings,
    VoidCallback? onClose,
  }) => PuzzleControlsPanel(
    title: '数独',
    description: '每行、每列和每个宫都填入不重复的数字。',
    closeTooltip: settingsOnly ? '关闭设置' : '隐藏设置栏',
    onClose: onClose ?? () => setState(() => _controlsSidebarVisible = false),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('新题设置'),
        const SizedBox(height: 8),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 6, label: Text('6×6')),
            ButtonSegment(value: 9, label: Text('9×9')),
          ],
          selected: {_size},
          showSelectedIcon: false,
          onSelectionChanged: (selection) {
            setState(() => _size = selection.first);
            refreshSettings?.call();
          },
        ),
        const SizedBox(height: 12),
        SegmentedButton<SudokuDifficulty>(
          segments: const [
            ButtonSegment(value: SudokuDifficulty.easy, label: Text('简单')),
            ButtonSegment(value: SudokuDifficulty.medium, label: Text('普通')),
            ButtonSegment(value: SudokuDifficulty.hard, label: Text('困难')),
          ],
          selected: {_difficulty},
          showSelectedIcon: false,
          onSelectionChanged: (selection) {
            setState(() => _difficulty = selection.first);
            refreshSettings?.call();
          },
        ),
        const SizedBox(height: 12),
        Text('线索密度 ${(100 * _clueDensity).round()}%'),
        Slider(
          value: _clueDensity,
          min: .25,
          max: .8,
          divisions: 22,
          label: '${(100 * _clueDensity).round()}%',
          onChanged: (value) {
            setState(() => _clueDensity = value);
            refreshSettings?.call();
          },
        ),
        const Text('控制题面已给数字比例；难度按实际推理技巧评估。'),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _isBusy ? null : () => unawaited(_newPuzzle()),
          icon: const Icon(Icons.refresh),
          label: const Text('按此设置生成新题'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _editingClues ? _finishEntry : _startEntry,
          icon: Icon(_editingClues ? Icons.check : Icons.edit_note),
          label: Text(_editingClues ? '完成录入' : '录入已有题目'),
        ),
        if (!settingsOnly) ...[
          const Divider(height: 28),
          FilledButton.icon(
            onPressed: _isBusy || _editingClues
                ? null
                : () => unawaited(_hint()),
            icon: const Icon(Icons.lightbulb_outline),
            label: const Text('提示'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _isBusy || _editingClues
                ? null
                : () => unawaited(_solve()),
            icon: const Icon(Icons.auto_fix_high),
            label: const Text('自动解题'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _check,
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('检查答案'),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(_status),
            ),
          ),
        ],
      ],
    ),
  );
}

enum _ShareMode { pageOnly, puzzleOnly, withProgress }

class _SudokuBoard extends StatelessWidget {
  const _SudokuBoard({
    required this.puzzle,
    required this.state,
    required this.selected,
    required this.scopeHighlights,
    required this.evidenceHighlights,
    required this.changeHighlights,
    required this.onSelect,
    required this.boardController,
    required this.onZoom,
    required this.showPuzzleSidebarButton,
    required this.showControlsSidebarButton,
    required this.onShowPuzzleSidebar,
    required this.onShowControlsSidebar,
  });

  final SudokuPuzzle puzzle;
  final SudokuState state;
  final CellId? selected;
  final Set<CellId> scopeHighlights;
  final Set<CellId> evidenceHighlights;
  final Set<CellId> changeHighlights;
  final ValueChanged<CellId> onSelect;
  final PuzzleBoardController boardController;
  final ValueChanged<double> onZoom;
  final bool showPuzzleSidebarButton;
  final bool showControlsSidebarButton;
  final VoidCallback onShowPuzzleSidebar;
  final VoidCallback onShowControlsSidebar;

  @override
  Widget build(BuildContext context) {
    final boardSize = puzzle.size * 58.0;
    return Stack(
      children: [
        Positioned.fill(
          child: Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                boardController.panBy(
                  Offset(-event.scrollDelta.dx, -event.scrollDelta.dy),
                );
              }
            },
            child: InteractiveViewer(
              transformationController: boardController.transformation,
              minScale: .65,
              maxScale: 5,
              constrained: false,
              boundaryMargin: const EdgeInsets.all(160),
              child: SizedBox(
                width: boardSize,
                height: boardSize,
                child: Column(
                  children: [
                    for (var row = 0; row < puzzle.size; row++)
                      Expanded(
                        child: Row(
                          children: [
                            for (var column = 0; column < puzzle.size; column++)
                              Expanded(child: _cell(row, column)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: 8,
          bottom: 8,
          child: Builder(
            builder: (context) => PuzzleBoardTools(
              onZoomIn: () => onZoom(1.25),
              onZoomOut: () => onZoom(.8),
              onReset: boardController.reset,
              onShowPuzzleSidebar: showPuzzleSidebarButton
                  ? onShowPuzzleSidebar
                  : null,
              onShowControlsSidebar: showControlsSidebarButton
                  ? onShowControlsSidebar
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _cell(int row, int column) {
    final cell = CellId(row, column);
    final clue = puzzle.givens[cell];
    final value = state.valueAt(cell);
    final peer =
        selected != null &&
        (selected!.row == row ||
            selected!.column == column ||
            (selected!.row ~/ puzzle.boxRows == row ~/ puzzle.boxRows &&
                selected!.column ~/ puzzle.boxColumns ==
                    column ~/ puzzle.boxColumns));
    final sameValue =
        selected != null &&
        state.valueAt(selected!) != null &&
        state.valueAt(selected!) == value;
    final background = changeHighlights.contains(cell)
        ? const Color(0x995C7CFF)
        : evidenceHighlights.contains(cell)
        ? const Color(0x888F6B22)
        : scopeHighlights.contains(cell)
        ? const Color(0x443F5599)
        : selected == cell
        ? const Color(0xAA536DB5)
        : peer || sameValue
        ? const Color(0x332F4E92)
        : const Color(0xFF101116);
    return GestureDetector(
      onTap: () => onSelect(cell),
      child: Container(
        decoration: BoxDecoration(
          color: background,
          border: Border(
            top: BorderSide(
              color: const Color(0xFF535766),
              width: row % puzzle.boxRows == 0 ? 2 : .6,
            ),
            left: BorderSide(
              color: const Color(0xFF535766),
              width: column % puzzle.boxColumns == 0 ? 2 : .6,
            ),
            right: BorderSide(
              color: const Color(0xFF535766),
              width: column == puzzle.size - 1 ? 2 : .6,
            ),
            bottom: BorderSide(
              color: const Color(0xFF535766),
              width: row == puzzle.size - 1 ? 2 : .6,
            ),
          ),
        ),
        child: Center(
          child: value != null
              ? Text(
                  '$value',
                  style: TextStyle(
                    fontSize: puzzle.size == 6 ? 26 : 23,
                    color: clue != null
                        ? const Color(0xFFE9EBF4)
                        : const Color(0xFFB9C8FF),
                    fontWeight: clue != null
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                )
              : _notes(state.notesAt(cell), puzzle.size),
        ),
      ),
    );
  }

  Widget _notes(Set<int> notes, int size) {
    const columns = 3;
    final rows = (size / columns).ceil();
    return Padding(
      padding: const EdgeInsets.all(1),
      child: Column(
        children: [
          for (var row = 0; row < rows; row++)
            Expanded(
              child: Row(
                children: [
                  for (var column = 0; column < columns; column++)
                    Expanded(
                      child: Center(
                        child: Text(
                          notes.contains(row * columns + column + 1)
                              ? '${row * columns + column + 1}'
                              : '',
                          style: const TextStyle(
                            fontSize: 9,
                            color: Color(0xFF9EA6C1),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
