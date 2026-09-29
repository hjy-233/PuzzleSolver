import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:puzzle_core/puzzle_core.dart';

import 'browser_url.dart';
import 'puzzle_widgets.dart';
import 'puzzle_share.dart';
import 'slitherlink_api.dart';

class SlitherlinkPage extends StatefulWidget {
  const SlitherlinkPage({super.key});

  @override
  State<SlitherlinkPage> createState() => _SlitherlinkPageState();
}

class _SlitherlinkPageState extends State<SlitherlinkPage> {
  static const _api = SlitherlinkApi();

  late SlitherlinkPuzzle _puzzle;
  late PuzzleSession<SlitherlinkState, SlitherlinkAction> _session;
  List<SolveStep<SlitherlinkAction>> _steps = [];
  SlitherlinkState? _stepBaseState;
  List<PuzzleTarget> _highlights = [];
  Timer? _highlightTimer;
  int? _selectedStepIndex;
  final _rowsController = TextEditingController(text: '5');
  final _columnsController = TextEditingController(text: '5');
  int _rows = 5;
  int _columns = 5;
  bool _editingClues = false;
  PuzzleDifficulty _difficulty = PuzzleDifficulty.normal;
  bool _includeBlankCells = true;
  double _clueDensity = 0.55;
  bool _isBusy = false;
  bool _completionDialogOpen = false;
  bool _completionDialogDismissed = false;
  bool _stepsVisible = true;
  bool _puzzleSidebarVisible = true;
  bool _controlsSidebarVisible = true;
  String _status = '左键画线，右键打叉。';

  @override
  void initState() {
    super.initState();
    final queryParameters = Map<String, String>.from(Uri.base.queryParameters)
      ..remove('code');
    final canonicalUrl = Uri.base.replace(
      path: '/slitherlink',
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );
    if (canonicalUrl.toString() != Uri.base.toString()) {
      BrowserUrl.replace(canonicalUrl);
    }
    final sharedPuzzle = Uri.base.queryParameters['p'];
    if (sharedPuzzle != null) {
      try {
        _puzzle = SlitherlinkShare.decodePuzzle(sharedPuzzle);
        _rows = _puzzle.topology.rows;
        _columns = _puzzle.topology.columns;
        _rowsController.text = '$_rows';
        _columnsController.text = '$_columns';
        _session = PuzzleSession.start(
          initialState: _puzzle.initialState,
          reducer: _puzzle.reduce,
        );
        final encodedProgress = Uri.base.queryParameters['s'];
        if (encodedProgress != null) {
          final progress = SlitherlinkShare.decodeProgress(
            encodedProgress,
            _puzzle.topology,
          );
          for (final entry in progress.edges.entries) {
            _session = _session.apply(
              SetSlitherlinkEdge(entry.key, entry.value),
            );
          }
          _status = '已从分享链接恢复题目和进度。';
        } else {
          _status = '已从分享链接打开题目。';
        }
        return;
      } on FormatException catch (error) {
        _status = '分享链接无效：${error.message}';
      }
    }
    _puzzle = SlitherlinkPuzzle(
      topology: const GridTopology(rows: 5, columns: 5),
      clues: const {},
    );
    _session = PuzzleSession.start(
      initialState: _puzzle.initialState,
      reducer: _puzzle.reduce,
    );
    unawaited(_newPuzzle());
  }

  void _replaceWithGeneratedPuzzle(SlitherlinkPuzzle puzzle) {
    _puzzle = puzzle;
    _rows = _puzzle.topology.rows;
    _columns = _puzzle.topology.columns;
    _rowsController.text = '$_rows';
    _columnsController.text = '$_columns';
    _editingClues = false;
    _session = PuzzleSession.start(
      initialState: _puzzle.initialState,
      reducer: _puzzle.reduce,
    );
    _steps = [];
    _stepBaseState = null;
    _highlights = [];
    _selectedStepIndex = null;
    _status = '已生成唯一解新题。左键画线，右键打叉。';
  }

  Future<void> _newPuzzle() async {
    final rows = int.tryParse(_rowsController.text);
    final columns = int.tryParse(_columnsController.text);
    if (rows == null || columns == null || rows < 1 || columns < 1) {
      setState(() => _status = '请填写有效的正整数行数和列数。');
      return;
    }
    _rows = rows;
    _columns = columns;
    if (rows * columns > 100) {
      setState(() => _status = '棋盘最多支持 100 格；请调小宽或高。');
      return;
    }
    _cancelHighlightFlash();
    setState(() {
      _isBusy = true;
      _status = '正在浏览器本地生成题目…';
    });
    try {
      final puzzle = await _api.generate(
        rows: rows,
        columns: columns,
        difficulty: _difficulty,
        includeBlankCells: _includeBlankCells,
        clueDensity: _clueDensity,
        useServer: false,
        onRetry: (attempts) {
          if (!mounted) return;
          setState(() => _status = '浏览器本地生成中，已重试 $attempts 次…');
        },
      );
      if (!mounted) return;
      setState(() {
        _replaceWithGeneratedPuzzle(puzzle);
        _isBusy = false;
        _status = '已由浏览器本地生成新题。左键画线，右键打叉。';
      });
      _syncCurrentUrl();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _status = '题目生成失败：$error';
      });
    }
  }

  void _startManualEntry() {
    final rows = int.tryParse(_rowsController.text) ?? 0;
    final columns = int.tryParse(_columnsController.text) ?? 0;
    if (rows < 1 || columns < 1 || rows * columns > 100) {
      setState(() => _status = '行数和列数须为正整数，棋盘最多 100 格。');
      return;
    }
    _cancelHighlightFlash();
    setState(() {
      _puzzle = SlitherlinkPuzzle(
        topology: GridTopology(rows: rows, columns: columns),
        clues: const {},
      );
      _session = PuzzleSession.start(
        initialState: _puzzle.initialState,
        reducer: _puzzle.reduce,
      );
      _steps = [];
      _stepBaseState = null;
      _highlights = [];
      _selectedStepIndex = null;
      _editingClues = true;
      _status = '点击格子填写 0–4；空白格留空。填完后点“完成录入”再自动解题。';
    });
    _syncCurrentUrl();
  }

  void _finishManualEntry() {
    setState(() {
      _editingClues = false;
      _status = _puzzle.clues.isEmpty
          ? '还没有录入数字。点击“录入已有题目”继续录入。'
          : '题目已录入 ${_puzzle.clues.length} 个数字，可以自动解题。';
    });
  }

  Future<void> _editClue(CellId cell) async {
    final controller = TextEditingController(
      text: _puzzle.clues[cell]?.toString() ?? '',
    );
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<_ClueEditResult>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('填写数字'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '0–4，留空表示空白格',
              border: OutlineInputBorder(),
            ),
            validator: (text) {
              if (text == null || text.trim().isEmpty) return null;
              final value = int.tryParse(text.trim());
              return value != null && value >= 0 && value <= 4
                  ? null
                  : '请输入 0 到 4 的整数';
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, const _ClueEditResult(null)),
            child: const Text('清除'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              final text = controller.text.trim();
              final value = text.isEmpty ? null : int.tryParse(text);
              Navigator.pop(context, _ClueEditResult(value));
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;
    final clues = Map<CellId, int>.from(_puzzle.clues);
    if (result.value == null) {
      clues.remove(cell);
    } else {
      clues[cell] = result.value!;
    }
    _cancelHighlightFlash();
    setState(() {
      _puzzle = SlitherlinkPuzzle(topology: _puzzle.topology, clues: clues);
      _session = PuzzleSession.start(
        initialState: _puzzle.initialState,
        reducer: _puzzle.reduce,
      );
      _steps = [];
      _stepBaseState = null;
      _highlights = [];
      _selectedStepIndex = null;
      _status = '题目已更新。';
    });
    _syncCurrentUrl();
  }

  void _updateDimension(String text, {required bool rows}) {
    final value = int.tryParse(text);
    if (value == null || value < 1) return;
    setState(() {
      if (rows) {
        _rows = value;
      } else {
        _columns = value;
      }
    });
  }

  void _handleGesture(PuzzleTarget target, PointerGesture gesture) {
    final action = _puzzle.actionFor(target, gesture, _session.state);
    if (action == null) {
      return;
    }
    _cancelHighlightFlash();
    setState(() {
      _session = _session.apply(action);
      _steps = [];
      _stepBaseState = null;
      _highlights = [];
      _selectedStepIndex = null;
      _status = gesture == PointerGesture.primaryTap ? '已画线。' : '已标记为不可能。';
    });
    _syncCurrentUrl();
    unawaited(_showCompletionDialogIfSolved());
  }

  void _handleStroke(Map<EdgeId, SlitherlinkEdgeState> edges) {
    if (edges.isEmpty) return;
    _cancelHighlightFlash();
    setState(() {
      _session = _session.apply(SetSlitherlinkEdges(edges));
      _steps = [];
      _stepBaseState = null;
      _highlights = [];
      _selectedStepIndex = null;
      _status = switch (edges.values.first) {
        SlitherlinkEdgeState.line => '已完成一笔连续画线。',
        SlitherlinkEdgeState.crossed => '已完成一笔连续打叉。',
        SlitherlinkEdgeState.empty => '已擦除一笔标记。',
      };
    });
    _syncCurrentUrl();
    unawaited(_showCompletionDialogIfSolved());
  }

  void _showHint() {
    final step = _puzzle.hint(_session.state);
    if (step == null) {
      setState(() => _status = '目前没有可直接应用的局部提示。');
      return;
    }
    final baseState = _steps.isEmpty ? _session.state : null;
    _cancelHighlightFlash();
    setState(() {
      for (final action in step.actions) {
        _session = _session.apply(action);
      }
      _steps.add(step);
      _stepBaseState ??= baseState;
      _highlights = [];
      _selectedStepIndex = null;
      _status = _explanationFor(step);
    });
    _syncCurrentUrl();
    unawaited(_showCompletionDialogIfSolved());
  }

  Future<void> _solve() async {
    if (_puzzle.check(_session.state).status == CheckStatus.solved) {
      setState(() => _status = '当前棋盘已经解完。');
      return;
    }
    try {
      if (_puzzle.clues.isEmpty) {
        setState(() => _status = '先录入题目数字，再自动解题。');
        return;
      }
      final baseState = _steps.isEmpty ? _session.state : null;
      setState(() {
        _isBusy = true;
        _status = '正在浏览器后台自动解题…';
      });
      final result = await _api.solve(
        _puzzle,
        _session.state,
        useServer: false,
      );
      if (!mounted) return;
      if (!result.hasUniqueSolution) {
        setState(() {
          _isBusy = false;
          _status = '当前局面不止一个解，不能自动确认唯一答案。';
        });
        return;
      }
      _cancelHighlightFlash();
      setState(() {
        for (final step in result.steps) {
          for (final action in step.actions) {
            _session = _session.apply(action);
          }
        }
        _steps = [..._steps, ...result.steps];
        _stepBaseState ??= baseState;
        _highlights = [];
        _selectedStepIndex = null;
        _isBusy = false;
        _status = '已由浏览器本地完成求解：${result.steps.length} 个推理步骤。';
      });
      _syncCurrentUrl();
      unawaited(_showCompletionDialogIfSolved());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _status = '自动解题失败：$error';
      });
    }
  }

  Future<void> _check() async {
    setState(() {
      _isBusy = true;
      _status = '正在本地检查答案…';
    });
    try {
      final result = await _api.check(_puzzle, _session.state);
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _status = switch (result.status) {
          CheckStatus.solved => '完成：所有数字满足条件，并且只有一个闭环。',
          CheckStatus.invalid => '当前状态矛盾：${_checkMessage(result.messageKey)}',
          CheckStatus.incomplete => '还没有完成；可以继续推理或使用提示。',
        };
      });
      if (result.status == CheckStatus.solved) {
        unawaited(_showCompletionDialogIfSolved());
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _status = '检查失败：$error';
      });
    }
  }

  void _undo() {
    if (!_session.canUndo) {
      return;
    }
    _cancelHighlightFlash();
    setState(() {
      _session = _session.undo();
      _steps = [];
      _stepBaseState = null;
      _highlights = [];
      _selectedStepIndex = null;
      _status = '已撤销一步。';
    });
    _syncCurrentUrl();
  }

  void _redo() {
    if (!_session.canRedo) {
      return;
    }
    _cancelHighlightFlash();
    setState(() {
      _session = _session.redo();
      _steps = [];
      _stepBaseState = null;
      _highlights = [];
      _selectedStepIndex = null;
      _status = '已重做一步。';
    });
    _syncCurrentUrl();
    unawaited(_showCompletionDialogIfSolved());
  }

  void _replayToStep(int index) {
    final actionCount = _steps
        .take(index + 1)
        .fold<int>(0, (count, step) => count + step.actions.length);
    _cancelHighlightFlash();
    setState(() {
      _session = PuzzleSession.start(
        initialState: _puzzle.initialState,
        reducer: _puzzle.reduce,
      );
      final baseState = _stepBaseState;
      if (baseState != null) {
        for (final edge in _puzzle.topology.allEdges) {
          final edgeState = baseState.stateOf(edge);
          if (edgeState != SlitherlinkEdgeState.empty) {
            _session = _session.apply(SetSlitherlinkEdge(edge, edgeState));
          }
        }
      }
      for (final action
          in _steps.take(index + 1).expand((step) => step.actions)) {
        _session = _session.apply(action);
      }
      _highlights = _targetsFor(_steps[index]);
      _selectedStepIndex = index;
      _status = '步骤 $actionCount：${_explanationFor(_steps[index])}';
    });
    _syncCurrentUrl();
    unawaited(_showCompletionDialogIfSolved());
    _highlightTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) {
        return;
      }
      setState(() => _highlights = []);
    });
  }

  void _cancelHighlightFlash() {
    _highlightTimer?.cancel();
    _highlightTimer = null;
  }

  Future<void> _showCompletionDialogIfSolved() async {
    if (_puzzle.check(_session.state).status != CheckStatus.solved) {
      _completionDialogDismissed = false;
      return;
    }
    if (_completionDialogOpen || _completionDialogDismissed) {
      return;
    }
    _completionDialogOpen = true;
    final startNewPuzzle = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('谜题完成！'),
        content: const Text('恭喜，你完成了这道数回。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('新题'),
          ),
        ],
      ),
    );
    _completionDialogOpen = false;
    if (!mounted) return;
    if (startNewPuzzle == true) {
      _completionDialogDismissed = false;
      unawaited(_newPuzzle());
    } else {
      _completionDialogDismissed = true;
    }
  }

  void _syncCurrentUrl() {
    final url = Uri.base.replace(
      path: '/slitherlink',
      queryParameters: {
        'p': SlitherlinkShare.encodePuzzle(_puzzle),
        's': SlitherlinkShare.encodeProgress(_session.state),
      },
    );
    BrowserUrl.replace(url);
  }

  Future<void> _share(_ShareMode mode) async {
    final queryParameters = <String, String>{
      if (mode != _ShareMode.puzzlePage)
        'p': SlitherlinkShare.encodePuzzle(_puzzle),
      if (mode == _ShareMode.puzzleAndProgress)
        's': SlitherlinkShare.encodeProgress(_session.state),
    };
    final url = Uri.base
        .replace(path: '/slitherlink', queryParameters: queryParameters)
        .toString();
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(switch (mode) {
          _ShareMode.puzzlePage => '数回页面链接已复制。',
          _ShareMode.puzzle => '当前题目链接已复制。',
          _ShareMode.puzzleAndProgress => '题目和当前进度链接已复制。',
        }),
      ),
    );
  }

  @override
  void dispose() {
    _cancelHighlightFlash();
    _rowsController.dispose();
    _columnsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final mobileLayout = screenWidth < 920;
    final content = _BoardPanel(
      puzzle: _puzzle,
      state: _session.state,
      highlights: _highlights,
      editingClues: _editingClues,
      onCellTap: _editClue,
      onGesture: _handleGesture,
      onStroke: _handleStroke,
      showPuzzleSidebarButton: !mobileLayout && !_puzzleSidebarVisible,
      showControlsSidebarButton: !mobileLayout && !_controlsSidebarVisible,
      onShowPuzzleSidebar: () => setState(() => _puzzleSidebarVisible = true),
      onShowControlsSidebar: () =>
          setState(() => _controlsSidebarVisible = true),
    );
    return Scaffold(
      drawer: mobileLayout ? _buildMobileDrawer(context) : null,
      appBar: PuzzleTopBar(
        mobile: mobileLayout,
        width: screenWidth,
        puzzleName: '数回',
        canUndo: _session.canUndo,
        canRedo: _session.canRedo,
        onShare: (choice) => unawaited(
          _share(switch (choice) {
            PuzzleShareChoice.page => _ShareMode.puzzlePage,
            PuzzleShareChoice.puzzle => _ShareMode.puzzle,
            PuzzleShareChoice.progress => _ShareMode.puzzleAndProgress,
          }),
        ),
        onNewPuzzle: _isBusy ? null : () => unawaited(_newPuzzle()),
        onUndo: _undo,
        onRedo: _redo,
      ),
      body: Builder(
        builder: (context) {
          final sidebar = PuzzleLibrarySidebar(
            puzzleName: '数回',
            puzzleIcon: Icons.route_outlined,
            selectedStepIndex: _selectedStepIndex,
            sizeLabel: '${_puzzle.topology.rows} × ${_puzzle.topology.columns}',
            otherPuzzleName: '数独',
            otherPuzzleIcon: Icons.grid_3x3,
            onSelectOtherPuzzle: () =>
                Navigator.pushReplacementNamed(context, '/sudoku'),
            steps: [
              for (final step in _steps)
                PuzzleStepItem(
                  title: _stepTitle(step),
                  description: _explanationFor(step),
                ),
            ],
            onStepTap: _replayToStep,
            onClose: () => setState(() => _puzzleSidebarVisible = false),
          );
          final controls = _buildControls(
            onClose: () => setState(() => _controlsSidebarVisible = false),
          );
          return PuzzleWorkspace(
            board: content,
            leftSidebar: sidebar,
            rightSidebar: controls,
            mobileControls: PuzzleMobileActionBar(
              actions: [
                PuzzleActionItem(
                  icon: Icons.lightbulb_outline,
                  label: '提示',
                  onPressed: !_isBusy && !_editingClues ? _showHint : null,
                ),
                PuzzleActionItem(
                  icon: Icons.auto_fix_high,
                  label: '自动解题',
                  onPressed: !_isBusy && !_editingClues ? _solve : null,
                ),
                PuzzleActionItem(
                  icon: Icons.fact_check_outlined,
                  label: '检查',
                  onPressed: !_isBusy && !_editingClues ? _check : null,
                ),
                PuzzleActionItem(
                  icon: Icons.more_horiz,
                  label: '设置',
                  onPressed: _showSettingsSheet,
                ),
              ],
            ),
            mobileSteps: PuzzleMobileStepsPanel(
              steps: [
                for (final step in _steps)
                  PuzzleStepItem(
                    title: _stepTitle(step),
                    description: _explanationFor(step),
                  ),
              ],
              selectedStepIndex: _selectedStepIndex,
              onStepTap: _replayToStep,
              onHide: () => setState(() => _stepsVisible = false),
              status: _status,
            ),
            showLeftSidebar: _puzzleSidebarVisible,
            showRightSidebar: _controlsSidebarVisible,
            showMobileSteps: _stepsVisible,
            onShowMobileSteps: () => setState(() => _stepsVisible = true),
          );
        },
      ),
    );
  }

  Widget _buildMobileDrawer(BuildContext context) => Drawer(
    child: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 24, 20, 12),
            child: Text('谜题库', style: TextStyle(fontSize: 18)),
          ),
          ListTile(
            selected: true,
            leading: const Icon(Icons.route_outlined),
            title: const Text('数回'),
            subtitle: Text(
              '${_puzzle.topology.rows} × ${_puzzle.topology.columns}',
            ),
            onTap: () => Navigator.of(context).pop(),
          ),
          ListTile(
            leading: const Icon(Icons.grid_3x3),
            title: const Text('数独'),
            onTap: () => Navigator.pushReplacementNamed(context, '/sudoku'),
          ),
        ],
      ),
    ),
  );

  _Controls _buildControls({
    bool settingsOnly = false,
    VoidCallback? refreshSettings,
    VoidCallback? onClose,
  }) => _Controls(
    onHint: _showHint,
    onSolve: _solve,
    onCheck: _check,
    editingClues: _editingClues,
    rowsController: _rowsController,
    columnsController: _columnsController,
    difficulty: _difficulty,
    includeBlankCells: _includeBlankCells,
    clueDensity: _clueDensity,
    onRowsChanged: (value) {
      _updateDimension(value, rows: true);
      refreshSettings?.call();
    },
    onColumnsChanged: (value) {
      _updateDimension(value, rows: false);
      refreshSettings?.call();
    },
    onDifficultyChanged: (value) {
      setState(() => _difficulty = value);
      refreshSettings?.call();
    },
    onIncludeBlankCellsChanged: (value) {
      setState(() => _includeBlankCells = value);
      refreshSettings?.call();
    },
    onClueDensityChanged: (value) {
      setState(() => _clueDensity = value);
      refreshSettings?.call();
    },
    onGenerate: () => unawaited(_newPuzzle()),
    onManualEntry: _startManualEntry,
    onFinishManualEntry: _finishManualEntry,
    isBusy: _isBusy,
    status: _status,
    settingsOnly: settingsOnly,
    onClose: onClose,
  );

  void _showSettingsSheet() {
    showPuzzleSettingsSheet(
      context,
      (sheetContext, refreshSettings) => _buildControls(
        settingsOnly: true,
        refreshSettings: refreshSettings,
        onClose: () => Navigator.pop(sheetContext),
      ),
    );
  }

  String _explanationFor(SolveStep<SlitherlinkAction> step) {
    final lineCount = step.actions.where((action) {
      return action is SetSlitherlinkEdge &&
          action.state == SlitherlinkEdgeState.line;
    }).length;
    final crossCount = step.actions.length - lineCount;
    final changes = [
      if (lineCount > 0) '画线 $lineCount',
      if (crossCount > 0) '打叉 $crossCount',
    ].join(' · ');
    return switch (step.ruleId) {
      'slitherlink.clueReached' => '此格数字已满足 · $changes',
      'slitherlink.remainingEdgesRequired' => '此格剩余边都要连线 · $changes',
      'slitherlink.zeroClues' => '所有 0 格周围的边都不能画线 · $changes',
      'slitherlink.vertexDegree' =>
        step.arguments['lines'] == 2
            ? '交点已有两条线，不能再接 · $changes'
            : '避免交点分叉或断开 · $changes',
      'slitherlink.preventOpenEnd' => '线经过此交点必须延续 · $changes',
      'slitherlink.insideOutside' => '根据区域内外关系确定这些边 · $changes',
      'slitherlink.fourCellWindow' => '比较这片四格区域的所有走法，找出共同边 · $changes',
      'slitherlink.loopClosed' => '单回路已闭合且满足数字，其余边都不能画线 · $changes',
      'slitherlink.assumptionContradiction' =>
        '反向尝试无法完成整圈 · 所以${_edgeStateName(step.arguments['result'])} · $changes',
      _ => changes,
    };
  }

  String _edgeStateName(Object? value) => switch (value) {
    'line' => '画线',
    'crossed' => '打叉',
    _ => '维持原状',
  };

  List<PuzzleTarget> _targetsFor(SolveStep<SlitherlinkAction> step) => [
    ...step.highlights,
    for (final action in step.actions)
      if (action case SetSlitherlinkEdge(:final edge)) EdgeTarget(edge),
  ];

  String _checkMessage(String? key) => switch (key) {
    'slitherlink.clueContradiction' => '某个数字格周围的线数量不可能满足。',
    'slitherlink.openOrBranchingLine' => '线条存在断头或分叉。',
    'slitherlink.multipleLoops' => '线条形成了多个环。',
    'slitherlink.noLoop' => '没有形成回路。',
    _ => '请检查当前标记。',
  };
}

final class _ClueEditResult {
  const _ClueEditResult(this.value);

  final int? value;
}

enum _ShareMode { puzzlePage, puzzle, puzzleAndProgress }

String _stepTitle(SolveStep<SlitherlinkAction> step) => switch (step.ruleId) {
  'slitherlink.clueReached' => '数字满足',
  'slitherlink.remainingEdgesRequired' => '必须画线',
  'slitherlink.zeroClues' => '0 格批量排除',
  'slitherlink.vertexDegree' => '交点规则',
  'slitherlink.preventOpenEnd' => '避免断线',
  'slitherlink.insideOutside' => '区域内外关系',
  'slitherlink.fourCellWindow' => '四格组合推理',
  'slitherlink.loopClosed' => '单回路完成',
  'slitherlink.assumptionContradiction' => '排除一边',
  _ => '推理',
};

class _Controls extends StatelessWidget {
  const _Controls({
    required this.onHint,
    required this.onSolve,
    required this.onCheck,
    required this.editingClues,
    required this.rowsController,
    required this.columnsController,
    required this.difficulty,
    required this.includeBlankCells,
    required this.clueDensity,
    required this.onRowsChanged,
    required this.onColumnsChanged,
    required this.onDifficultyChanged,
    required this.onIncludeBlankCellsChanged,
    required this.onClueDensityChanged,
    required this.onGenerate,
    required this.onManualEntry,
    required this.onFinishManualEntry,
    required this.isBusy,
    required this.status,
    this.onClose,
    this.settingsOnly = false,
  });

  final VoidCallback onHint;
  final VoidCallback onSolve;
  final VoidCallback onCheck;
  final bool editingClues;
  final TextEditingController rowsController;
  final TextEditingController columnsController;
  final PuzzleDifficulty difficulty;
  final bool includeBlankCells;
  final double clueDensity;
  final ValueChanged<String> onRowsChanged;
  final ValueChanged<String> onColumnsChanged;
  final ValueChanged<PuzzleDifficulty> onDifficultyChanged;
  final ValueChanged<bool> onIncludeBlankCellsChanged;
  final ValueChanged<double> onClueDensityChanged;
  final VoidCallback onGenerate;
  final VoidCallback onManualEntry;
  final VoidCallback onFinishManualEntry;
  final bool isBusy;
  final String status;
  final VoidCallback? onClose;
  final bool settingsOnly;

  @override
  Widget build(BuildContext context) => PuzzleControlsPanel(
    title: '数回',
    description: '让所有线段组成一个闭环，并让每个数字格周围的线数相等。',
    closeTooltip: settingsOnly ? '关闭设置' : '隐藏设置栏',
    onClose: onClose,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('新题设置', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: rowsController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '高（行）',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: onRowsChanged,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: columnsController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '宽（列）',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: onColumnsChanged,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text('自定义尺寸；最多 100 格，尺寸越大生成越慢。'),
        const SizedBox(height: 12),
        const Text('难度'),
        const SizedBox(height: 6),
        SegmentedButton<PuzzleDifficulty>(
          segments: const [
            ButtonSegment(value: PuzzleDifficulty.easy, label: Text('简单')),
            ButtonSegment(value: PuzzleDifficulty.normal, label: Text('普通')),
            ButtonSegment(value: PuzzleDifficulty.hard, label: Text('困难')),
          ],
          selected: {difficulty},
          showSelectedIcon: false,
          onSelectionChanged: (selection) {
            if (selection.isNotEmpty) onDifficultyChanged(selection.first);
          },
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('允许空白格'),
          subtitle: const Text('关闭后每个格子都会给数字'),
          value: includeBlankCells,
          onChanged: onIncludeBlankCellsChanged,
        ),
        Text('生成密度 ${(clueDensity * 100).round()}%'),
        Slider(
          value: clueDensity,
          min: 0,
          max: 1,
          divisions: 20,
          label: '${(clueDensity * 100).round()}%',
          onChanged: onClueDensityChanged,
        ),
        const Text('基准值为 50%；调高后数字更多、空白格更少。'),
        const SizedBox(height: 8),
        if (editingClues)
          OutlinedButton.icon(
            onPressed: isBusy ? null : onFinishManualEntry,
            icon: const Icon(Icons.check),
            label: const Text('完成录入'),
          )
        else
          OutlinedButton.icon(
            onPressed: isBusy ? null : onManualEntry,
            icon: const Icon(Icons.edit_note),
            label: const Text('录入已有题目'),
          ),
        if (!settingsOnly) ...[
          const Divider(height: 32),
          FilledButton.icon(
            onPressed: editingClues || isBusy ? null : onHint,
            icon: const Icon(Icons.lightbulb_outline),
            label: const Text('提示'),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: editingClues || isBusy ? null : onSolve,
            icon: const Icon(Icons.auto_fix_high),
            label: const Text('自动解题'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: editingClues || isBusy ? null : onCheck,
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('检查答案'),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 19),
                  const SizedBox(width: 10),
                  Expanded(child: Text(status)),
                ],
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

class _BoardPanel extends StatefulWidget {
  const _BoardPanel({
    required this.puzzle,
    required this.state,
    required this.highlights,
    required this.editingClues,
    required this.onCellTap,
    required this.onGesture,
    required this.onStroke,
    required this.showPuzzleSidebarButton,
    required this.showControlsSidebarButton,
    required this.onShowPuzzleSidebar,
    required this.onShowControlsSidebar,
  });

  final SlitherlinkPuzzle puzzle;
  final SlitherlinkState state;
  final List<PuzzleTarget> highlights;
  final bool editingClues;
  final ValueChanged<CellId> onCellTap;
  final void Function(PuzzleTarget, PointerGesture) onGesture;
  final ValueChanged<Map<EdgeId, SlitherlinkEdgeState>> onStroke;
  final bool showPuzzleSidebarButton;
  final bool showControlsSidebarButton;
  final VoidCallback onShowPuzzleSidebar;
  final VoidCallback onShowControlsSidebar;

  @override
  State<_BoardPanel> createState() => _BoardPanelState();
}

class _BoardPanelState extends State<_BoardPanel> {
  final _boardController = PuzzleBoardController();
  final _focusNode = FocusNode();
  final _touchPositions = <int, Offset>{};
  final _canvasTouchPointers = <int>{};
  final _strokeChanges = <EdgeId, SlitherlinkEdgeState>{};
  final _strokeVisited = <EdgeId>{};
  int? _strokePointer;
  int? _pendingTapPointer;
  Offset? _touchDownPosition;
  Offset? _lastStrokePosition;
  EdgeId? _pendingTapEdge;
  DateTime? _pendingTapTime;
  Timer? _pendingTapTimer;
  SlitherlinkEdgeState? _strokeState;
  bool _touchDragStarted = false;
  bool _multiTouchActive = false;
  Map<EdgeId, SlitherlinkEdgeState> _previewEdges = {};

  @override
  void didUpdateWidget(covariant _BoardPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.puzzle, widget.puzzle)) {
      _boardController.reset();
    }
  }

  @override
  void dispose() {
    _pendingTapTimer?.cancel();
    _focusNode.dispose();
    _boardController.dispose();
    super.dispose();
  }

  void _panBy(Offset delta) {
    _boardController.panBy(delta);
  }

  void _zoomAt(Offset oldFocalPoint, Offset newFocalPoint, double factor) {
    _boardController.zoomAt(oldFocalPoint, newFocalPoint, factor);
  }

  void _onViewportPointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch) return;
    _touchPositions[event.pointer] = event.localPosition;
    if (_touchPositions.length == 1) return;
    _commitPendingTap();
    _multiTouchActive = true;
    if (_strokePointer != null) _finishStroke();
    _strokePointer = null;
    _pendingTapPointer = null;
  }

  void _onViewportPointerMove(PointerMoveEvent event) {
    if (!_touchPositions.containsKey(event.pointer) ||
        _touchPositions.length < 2) {
      return;
    }
    final oldFocalPoint = _touchCentroid();
    final oldDistance = _touchDistance();
    _touchPositions[event.pointer] = event.localPosition;
    final newFocalPoint = _touchCentroid();
    final newDistance = _touchDistance();
    if (oldDistance > 0 && newDistance > 0) {
      _zoomAt(oldFocalPoint, newFocalPoint, newDistance / oldDistance);
    } else {
      _panBy(newFocalPoint - oldFocalPoint);
    }
  }

  void _onViewportPointerUp(PointerEvent event) {
    _touchPositions.remove(event.pointer);
    if (_touchPositions.isEmpty) _multiTouchActive = false;
  }

  Offset _touchCentroid() {
    final points = _touchPositions.values.take(2).toList();
    if (points.length < 2) return points.firstOrNull ?? Offset.zero;
    return (points[0] + points[1]) / 2;
  }

  double _touchDistance() {
    final points = _touchPositions.values.take(2).toList();
    return points.length < 2 ? 0 : (points[1] - points[0]).distance;
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      _panBy(Offset(-event.scrollDelta.dx, -event.scrollDelta.dy));
    }
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final delta = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft => const Offset(48, 0),
      LogicalKeyboardKey.arrowRight => const Offset(-48, 0),
      LogicalKeyboardKey.arrowUp => const Offset(0, 48),
      LogicalKeyboardKey.arrowDown => const Offset(0, -48),
      _ => null,
    };
    if (delta == null) return KeyEventResult.ignored;
    _panBy(delta);
    return KeyEventResult.handled;
  }

  void _onCanvasPointerDown(PointerDownEvent event, _BoardGeometry geometry) {
    _focusNode.requestFocus();
    if (widget.editingClues) return;
    if (event.kind == PointerDeviceKind.touch) {
      _canvasTouchPointers.add(event.pointer);
      if (_canvasTouchPointers.length > 1) {
        _multiTouchActive = true;
        if (_strokePointer != null) _finishStroke();
        _strokePointer = null;
        _pendingTapPointer = null;
        return;
      }
      _pendingTapPointer = event.pointer;
      _touchDownPosition = event.localPosition;
      _touchDragStarted = false;
      return;
    }
    if (event.kind != PointerDeviceKind.mouse) return;
    final gesture = (event.buttons & 2) != 0
        ? PointerGesture.secondaryTap
        : (event.buttons & 1) != 0
        ? PointerGesture.primaryTap
        : null;
    if (gesture != null) {
      _beginStroke(event.pointer, event.localPosition, gesture, geometry);
    }
  }

  void _onCanvasPointerMove(PointerMoveEvent event, _BoardGeometry geometry) {
    if (event.kind == PointerDeviceKind.touch &&
        event.pointer == _pendingTapPointer &&
        !_touchDragStarted &&
        !_multiTouchActive) {
      final downPosition = _touchDownPosition;
      if (downPosition != null &&
          (event.localPosition - downPosition).distance > kTouchSlop) {
        _commitPendingTap();
        _touchDragStarted = true;
        _beginStroke(
          event.pointer,
          downPosition,
          PointerGesture.primaryTap,
          geometry,
        );
      }
    }
    if (event.pointer == _strokePointer) {
      _paintSegment(event.localPosition, geometry);
    }
  }

  void _onCanvasPointerUp(PointerEvent event, _BoardGeometry geometry) {
    if (event.kind == PointerDeviceKind.touch) {
      _canvasTouchPointers.remove(event.pointer);
      if (event.pointer == _strokePointer && _touchDragStarted) {
        _finishStroke();
      } else if (event.pointer == _pendingTapPointer &&
          !_multiTouchActive &&
          !_touchDragStarted) {
        final cell = widget.editingClues
            ? geometry.hitCell(event.localPosition)
            : null;
        if (cell != null) {
          widget.onCellTap(cell);
        } else {
          final edge = geometry.hitEdge(event.localPosition);
          if (edge != null) _registerTouchTap(edge);
        }
      }
      if (_canvasTouchPointers.isEmpty) _multiTouchActive = false;
      _pendingTapPointer = null;
      _touchDownPosition = null;
      _touchDragStarted = false;
      return;
    }
    if (event.pointer == _strokePointer) {
      _finishStroke();
    } else if (widget.editingClues && event is PointerUpEvent) {
      final cell = geometry.hitCell(event.localPosition);
      if (cell != null) widget.onCellTap(cell);
    }
  }

  void _onCanvasPointerCancel(PointerCancelEvent event) {
    _canvasTouchPointers.remove(event.pointer);
    if (event.pointer == _strokePointer) _finishStroke();
    if (event.pointer == _pendingTapPointer) _pendingTapPointer = null;
    if (_canvasTouchPointers.isEmpty) _multiTouchActive = false;
  }

  void _registerTouchTap(EdgeId edge) {
    final now = DateTime.now();
    final previousEdge = _pendingTapEdge;
    final previousTime = _pendingTapTime;
    if (previousEdge == edge &&
        previousTime != null &&
        now.difference(previousTime) <= kDoubleTapTimeout) {
      _pendingTapTimer?.cancel();
      _pendingTapTimer = null;
      _pendingTapEdge = null;
      _pendingTapTime = null;
      widget.onGesture(EdgeTarget(edge), PointerGesture.secondaryTap);
      return;
    }
    _commitPendingTap();
    _pendingTapEdge = edge;
    _pendingTapTime = now;
    _pendingTapTimer = Timer(kDoubleTapTimeout, _commitPendingTap);
  }

  void _commitPendingTap() {
    _pendingTapTimer?.cancel();
    _pendingTapTimer = null;
    final edge = _pendingTapEdge;
    _pendingTapEdge = null;
    _pendingTapTime = null;
    if (edge != null && mounted) {
      widget.onGesture(EdgeTarget(edge), PointerGesture.primaryTap);
    }
  }

  void _beginStroke(
    int pointer,
    Offset position,
    PointerGesture gesture,
    _BoardGeometry geometry,
  ) {
    final edge = geometry.hitEdge(position);
    if (edge == null) return;
    _strokePointer = pointer;
    _lastStrokePosition = position;
    _strokeVisited.clear();
    _strokeChanges.clear();
    final current = widget.state.stateOf(edge);
    _strokeState = switch (gesture) {
      PointerGesture.primaryTap =>
        current == SlitherlinkEdgeState.line
            ? SlitherlinkEdgeState.empty
            : SlitherlinkEdgeState.line,
      PointerGesture.secondaryTap =>
        current == SlitherlinkEdgeState.crossed
            ? SlitherlinkEdgeState.empty
            : SlitherlinkEdgeState.crossed,
      PointerGesture.doubleTap || PointerGesture.longPress => null,
    };
    _paintEdge(edge);
  }

  void _paintSegment(Offset position, _BoardGeometry geometry) {
    final previous = _lastStrokePosition;
    if (previous == null) return;
    final distance = (position - previous).distance;
    final spacing = math.max(geometry.cellSize * .25, 1);
    final sampleCount = (distance / spacing).ceil().clamp(1, 256);
    for (var sample = 1; sample <= sampleCount; sample++) {
      final point = Offset.lerp(previous, position, sample / sampleCount);
      if (point != null) {
        final edge = geometry.hitEdge(point);
        if (edge != null) _paintEdge(edge);
      }
    }
    _lastStrokePosition = position;
  }

  void _paintEdge(EdgeId edge) {
    if (!_strokeVisited.add(edge)) return;
    final targetState = _strokeState;
    if (targetState == null) return;
    final current = widget.state.stateOf(edge);
    if (current == targetState) return;
    _strokeChanges[edge] = targetState;
    setState(() => _previewEdges = Map.of(_strokeChanges));
  }

  void _finishStroke() {
    _strokePointer = null;
    _lastStrokePosition = null;
    _strokeState = null;
    final changes = Map<EdgeId, SlitherlinkEdgeState>.of(_strokeChanges);
    _strokeChanges.clear();
    _strokeVisited.clear();
    if (mounted) setState(() => _previewEdges = {});
    if (changes.isNotEmpty) widget.onStroke(changes);
  }

  void _zoomBy(double factor) {
    final viewport = context.size;
    if (viewport == null) return;
    _boardController.zoomCentered(viewport, factor);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => ClipRect(
      child: Focus(
        focusNode: _focusNode,
        onKeyEvent: _onKeyEvent,
        child: Listener(
          onPointerDown: _onViewportPointerDown,
          onPointerMove: _onViewportPointerMove,
          onPointerUp: _onViewportPointerUp,
          onPointerCancel: _onViewportPointerUp,
          onPointerSignal: _onPointerSignal,
          child: Stack(
            fit: StackFit.expand,
            children: [
              InteractiveViewer(
                transformationController: _boardController.transformation,
                panEnabled: false,
                scaleEnabled: false,
                minScale: .7,
                maxScale: 5,
                boundaryMargin: const EdgeInsets.all(120),
                child: SizedBox(
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: LayoutBuilder(
                          builder: (context, boardConstraints) {
                            final geometry = _BoardGeometry(
                              widget.puzzle.topology,
                              boardConstraints.biggest,
                            );
                            return Listener(
                              behavior: HitTestBehavior.opaque,
                              onPointerDown: (event) =>
                                  _onCanvasPointerDown(event, geometry),
                              onPointerMove: (event) =>
                                  _onCanvasPointerMove(event, geometry),
                              onPointerUp: (event) =>
                                  _onCanvasPointerUp(event, geometry),
                              onPointerCancel: _onCanvasPointerCancel,
                              child: CustomPaint(
                                painter: _SlitherlinkPainter(
                                  puzzle: widget.puzzle,
                                  state: widget.state.withEdges(_previewEdges),
                                  highlights: widget.highlights,
                                  geometry: geometry,
                                ),
                                child: const SizedBox.expand(),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 8,
                bottom: 8,
                child: PuzzleBoardTools(
                  onZoomIn: () => _zoomBy(1.25),
                  onZoomOut: () => _zoomBy(.8),
                  onReset: _boardController.reset,
                  onShowPuzzleSidebar: widget.showPuzzleSidebarButton
                      ? widget.onShowPuzzleSidebar
                      : null,
                  onShowControlsSidebar: widget.showControlsSidebarButton
                      ? widget.onShowControlsSidebar
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _BoardGeometry {
  const _BoardGeometry(this.topology, this.size);

  static const _edgeHitRadiusFactor = .28;

  final GridTopology topology;
  final Size size;

  double get cellSize =>
      math.min(size.width / topology.columns, size.height / topology.rows);
  Offset get origin => Offset(
    (size.width - cellSize * topology.columns) / 2,
    (size.height - cellSize * topology.rows) / 2,
  );

  Offset vertex(VertexId id) =>
      origin + Offset(id.column * cellSize, id.row * cellSize);

  Offset cellCenter(CellId id) =>
      origin + Offset((id.column + .5) * cellSize, (id.row + .5) * cellSize);

  CellId? hitCell(Offset point) {
    final relative = point - origin;
    final column = (relative.dx / cellSize).floor();
    final row = (relative.dy / cellSize).floor();
    final cell = CellId(row, column);
    return topology.containsCell(cell) ? cell : null;
  }

  EdgeId? hitEdge(Offset point) {
    EdgeId? closest;
    var closestDistance = cellSize * _edgeHitRadiusFactor;
    for (final edge in topology.allEdges) {
      final vertices = topology.verticesOf(edge);
      final distance = _distanceToSegment(
        point,
        vertex(vertices.first),
        vertex(vertices.last),
      );
      if (distance < closestDistance) {
        closest = edge;
        closestDistance = distance;
      }
    }
    return closest;
  }

  double _distanceToSegment(Offset point, Offset start, Offset end) {
    final vector = end - start;
    final lengthSquared = vector.dx * vector.dx + vector.dy * vector.dy;
    if (lengthSquared == 0) return (point - start).distance;
    final relative = point - start;
    final projection =
        ((relative.dx * vector.dx + relative.dy * vector.dy) / lengthSquared)
            .clamp(0.0, 1.0)
            .toDouble();
    return (point - (start + vector * projection)).distance;
  }
}

class _SlitherlinkPainter extends CustomPainter {
  const _SlitherlinkPainter({
    required this.puzzle,
    required this.state,
    required this.highlights,
    required this.geometry,
  });

  final SlitherlinkPuzzle puzzle;
  final SlitherlinkState state;
  final List<PuzzleTarget> highlights;
  final _BoardGeometry geometry;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFF3B3F4D)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final linePaint = Paint()
      ..color = const Color(0xFF9CB3FF)
      ..strokeWidth = math.max(3, geometry.cellSize * .075)
      ..strokeCap = StrokeCap.round;
    final crossPaint = Paint()
      ..color = const Color(0xFF8C91A0)
      ..strokeWidth = math.max(1.5, geometry.cellSize * .022);
    final cellHighlightPaint = Paint()
      ..color = const Color(0x335C7CFF)
      ..style = PaintingStyle.fill;
    final cellHighlightBorderPaint = Paint()
      ..color = const Color(0xFFB9C8FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2, geometry.cellSize * .035);
    final edgeHighlightPaint = Paint()
      ..color = const Color(0xFFFFD166)
      ..strokeWidth = math.max(7, geometry.cellSize * .16)
      ..strokeCap = StrokeCap.round;
    final vertexHighlightPaint = Paint()..color = const Color(0xFFFFD166);
    final dotPaint = Paint()..color = const Color(0xFFE1E4F0);
    final clueStyle = TextStyle(
      color: const Color(0xFFE9EBF4),
      fontSize: geometry.cellSize * .35,
      fontWeight: FontWeight.w600,
    );

    for (var row = 0; row <= puzzle.topology.rows; row++) {
      final left = geometry.vertex(VertexId(row, 0));
      final right = geometry.vertex(VertexId(row, puzzle.topology.columns));
      canvas.drawLine(left, right, gridPaint);
    }
    for (var column = 0; column <= puzzle.topology.columns; column++) {
      final top = geometry.vertex(VertexId(0, column));
      final bottom = geometry.vertex(VertexId(puzzle.topology.rows, column));
      canvas.drawLine(top, bottom, gridPaint);
    }
    final highlightedCells = <CellId>{
      for (final target in highlights)
        if (target case CellTarget(:final cell)) cell,
    };
    for (final cell in highlightedCells) {
      final topLeft = geometry.vertex(VertexId(cell.row, cell.column));
      final rect = Rect.fromLTWH(
        topLeft.dx,
        topLeft.dy,
        geometry.cellSize,
        geometry.cellSize,
      ).deflate(2);
      canvas.drawRect(rect, cellHighlightPaint);
      canvas.drawRect(rect, cellHighlightBorderPaint);
    }
    for (final entry in puzzle.clues.entries) {
      final painter = TextPainter(
        text: TextSpan(text: '${entry.value}', style: clueStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        geometry.cellCenter(entry.key) -
            Offset(painter.width / 2, painter.height / 2),
      );
    }
    final highlightedEdges = <EdgeId>{
      for (final target in highlights)
        if (target case EdgeTarget(:final edge)) edge,
    };
    for (final edge in puzzle.topology.allEdges) {
      final vertices = puzzle.topology.verticesOf(edge);
      final start = geometry.vertex(vertices.first);
      final end = geometry.vertex(vertices.last);
      if (highlightedEdges.contains(edge)) {
        canvas.drawLine(start, end, edgeHighlightPaint);
      }
      switch (state.stateOf(edge)) {
        case SlitherlinkEdgeState.line:
          canvas.drawLine(start, end, linePaint);
        case SlitherlinkEdgeState.crossed:
          _drawCross(canvas, (start + end) / 2, crossPaint);
        case SlitherlinkEdgeState.empty:
          break;
      }
    }
    final highlightedVertices = <VertexId>{
      for (final target in highlights)
        if (target case VertexTarget(:final vertex)) vertex,
    };
    for (var row = 0; row <= puzzle.topology.rows; row++) {
      for (var column = 0; column <= puzzle.topology.columns; column++) {
        final vertex = VertexId(row, column);
        if (highlightedVertices.contains(vertex)) {
          canvas.drawCircle(
            geometry.vertex(vertex),
            math.max(7, geometry.cellSize * .11),
            vertexHighlightPaint,
          );
        }
        canvas.drawCircle(
          geometry.vertex(vertex),
          math.max(2.5, geometry.cellSize * .045),
          dotPaint,
        );
      }
    }
  }

  void _drawCross(Canvas canvas, Offset center, Paint paint) {
    final radius = geometry.cellSize * .085;
    canvas.drawLine(
      center - Offset(radius, radius),
      center + Offset(radius, radius),
      paint,
    );
    canvas.drawLine(
      center + Offset(radius, -radius),
      center - Offset(radius, -radius),
      paint,
    );
  }

  @override
  bool shouldRepaint(_SlitherlinkPainter oldDelegate) =>
      oldDelegate.puzzle != puzzle ||
      oldDelegate.state != state ||
      oldDelegate.highlights != highlights ||
      oldDelegate.geometry.size != geometry.size;
}
