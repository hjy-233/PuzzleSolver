import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:puzzle_core/puzzle_core.dart';

class SlitherlinkPage extends StatefulWidget {
  const SlitherlinkPage({super.key});

  @override
  State<SlitherlinkPage> createState() => _SlitherlinkPageState();
}

class _SlitherlinkPageState extends State<SlitherlinkPage> {
  static const _generator = SlitherlinkGenerator();
  static const _solver = SlitherlinkSolver();

  late SlitherlinkPuzzle _puzzle;
  late PuzzleSession<SlitherlinkState, SlitherlinkAction> _session;
  List<SolveStep<SlitherlinkAction>> _steps = [];
  SlitherlinkState? _stepBaseState;
  List<PuzzleTarget> _highlights = [];
  Timer? _highlightTimer;
  int? _selectedStepIndex;
  int _boardSize = 5;
  PuzzleDifficulty _difficulty = PuzzleDifficulty.normal;
  bool _includeBlankCells = true;
  String _status = '左键画线，右键打叉。';

  @override
  void initState() {
    super.initState();
    _replaceWithGeneratedPuzzle();
  }

  void _replaceWithGeneratedPuzzle() {
    final generated = _generator.generate(
      SlitherlinkGenerationOptions(
        rows: _boardSize,
        columns: _boardSize,
        difficulty: _difficulty,
        includeBlankCells: _includeBlankCells,
        seed: DateTime.now().microsecondsSinceEpoch,
      ),
    );
    _puzzle = generated.puzzle;
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

  void _newPuzzle() {
    _cancelHighlightFlash();
    setState(_replaceWithGeneratedPuzzle);
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
  }

  void _solve() {
    if (_puzzle.check(_session.state).status == CheckStatus.solved) {
      setState(() => _status = '当前棋盘已经解完。');
      return;
    }
    try {
      final baseState = _steps.isEmpty ? _session.state : null;
      final result = _solver.solve(_puzzle, initialState: _session.state);
      if (!result.hasUniqueSolution) {
        setState(() {
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
        _status = '自动解题完成：${result.steps.length} 个可解释步骤。';
      });
    } on StateError catch (error) {
      setState(() => _status = '自动解题失败：${error.message}');
    }
  }

  void _check() {
    final result = _puzzle.check(_session.state);
    setState(() {
      _status = switch (result.status) {
        CheckStatus.solved => '完成：所有数字满足条件，并且只有一个闭环。',
        CheckStatus.invalid => '当前状态矛盾：${_checkMessage(result.messageKey)}',
        CheckStatus.incomplete => '还没有完成；可以继续推理或使用提示。',
      };
    });
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
      _status = '已回放（共 $actionCount 个确定操作）：${_explanationFor(_steps[index])}';
    });
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

  @override
  void dispose() {
    _cancelHighlightFlash();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = _BoardPanel(
      puzzle: _puzzle,
      state: _session.state,
      highlights: _highlights,
      onGesture: _handleGesture,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('PuzzleSolver'),
        actions: [
          TextButton.icon(
            onPressed: _newPuzzle,
            icon: const Icon(Icons.refresh),
            label: const Text('新题'),
          ),
          TextButton.icon(
            onPressed: _session.canUndo ? _undo : null,
            icon: const Icon(Icons.undo),
            label: const Text('撤销'),
          ),
          TextButton.icon(
            onPressed: _session.canRedo ? _redo : null,
            icon: const Icon(Icons.redo),
            label: const Text('重做'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final sidebar = _Sidebar(
            steps: _steps,
            onStepTap: _replayToStep,
            descriptionFor: _explanationFor,
            selectedStepIndex: _selectedStepIndex,
            sizeLabel: '${_puzzle.topology.rows} × ${_puzzle.topology.columns}',
          );
          final controls = _Controls(
            onHint: _showHint,
            onSolve: _solve,
            onCheck: _check,
            boardSize: _boardSize,
            difficulty: _difficulty,
            includeBlankCells: _includeBlankCells,
            onBoardSizeChanged: (value) => setState(() => _boardSize = value),
            onDifficultyChanged: (value) => setState(() => _difficulty = value),
            onIncludeBlankCellsChanged: (value) =>
                setState(() => _includeBlankCells = value),
            onGenerate: _newPuzzle,
            status: _status,
          );
          if (constraints.maxWidth < 920) {
            return ListView(
              children: [
                SizedBox(height: 400, child: content),
                controls,
                SizedBox(height: 190, child: sidebar),
              ],
            );
          }
          return Row(
            children: [
              SizedBox(width: 250, child: sidebar),
              const VerticalDivider(width: 1),
              Expanded(child: content),
              const VerticalDivider(width: 1),
              SizedBox(width: 310, child: controls),
            ],
          );
        },
      ),
    );
  }

  String _explanationFor(
    SolveStep<SlitherlinkAction> step,
  ) => switch (step.ruleId) {
    'slitherlink.clueReached' =>
      '高亮数字周围已经画了 ${step.arguments['lines']} 条线，刚好满足它的要求；'
          '标亮的 ${step.actions.length} 条边都不能再画线。',
    'slitherlink.remainingEdgesRequired' =>
      '高亮数字还差 '
          '${(step.arguments['clue'] as int) - (step.arguments['lines'] as int)} 条线，'
          '而周围正好只剩 ${step.actions.length} 条可选边；标亮的边都必须画线。',
    'slitherlink.vertexDegree' => _vertexExplanation(step),
    'slitherlink.preventOpenEnd' =>
      '高亮交点已有一条线，并且只剩一个可连接的方向；'
          '为了不让线在这里断头，标亮边必须画线。',
    'slitherlink.assumptionContradiction' =>
      '尝试让标亮边${_edgeStateName(step.arguments['assumed'])}会让题目无解；'
          '因此它只能${_edgeStateName(step.arguments['result'])}。',
    _ => '已应用一条规则。',
  };

  String _vertexExplanation(SolveStep<SlitherlinkAction> step) {
    if (step.arguments['lines'] == 2) {
      return '高亮交点已经连接两条线；为了不出现分叉，'
          '其余 ${step.actions.length} 条边都不能画线。';
    }
    return '高亮交点周围只剩 ${step.actions.length} 条未知边；'
        '若再画线会留下断头，所以这些边不能画线。';
  }

  String _edgeStateName(Object? value) => switch (value) {
    'line' => '画线',
    'crossed' => '不画线',
    _ => '保持原状',
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

String _stepTitle(SolveStep<SlitherlinkAction> step) => switch (step.ruleId) {
  'slitherlink.clueReached' => '数字已满足',
  'slitherlink.remainingEdgesRequired' => '剩余边必须画线',
  'slitherlink.vertexDegree' => '交点不能分叉',
  'slitherlink.preventOpenEnd' => '避免线条断头',
  'slitherlink.assumptionContradiction' => '反证确定边状态',
  _ => '推理步骤',
};

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.steps,
    required this.onStepTap,
    required this.descriptionFor,
    required this.selectedStepIndex,
    required this.sizeLabel,
  });

  final List<SolveStep<SlitherlinkAction>> steps;
  final ValueChanged<int> onStepTap;
  final String Function(SolveStep<SlitherlinkAction> step) descriptionFor;
  final int? selectedStepIndex;
  final String sizeLabel;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFF14161D),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 24, 20, 10),
          child: Text(
            '谜题库',
            style: TextStyle(fontSize: 14, color: Color(0xFFB6B9C7)),
          ),
        ),
        ListTile(
          selected: true,
          leading: const Icon(Icons.route_outlined),
          title: const Text('数回'),
          subtitle: Text('$sizeLabel 唯一解生成题'),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Text(
            '推理步骤 ${steps.length}',
            style: const TextStyle(fontSize: 14, color: Color(0xFFB6B9C7)),
          ),
        ),
        Expanded(
          child: steps.isEmpty
              ? const Center(
                  child: Text(
                    '还没有提示步骤',
                    style: TextStyle(color: Color(0xFF9094A3)),
                  ),
                )
              : ListView.builder(
                  itemCount: steps.length,
                  itemBuilder: (context, index) => ListTile(
                    selected: index == selectedStepIndex,
                    leading: CircleAvatar(
                      radius: 12,
                      child: Text('${index + 1}'),
                    ),
                    title: Text(_stepTitle(steps[index])),
                    subtitle: Text(
                      descriptionFor(steps[index]),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => onStepTap(index),
                  ),
                ),
        ),
      ],
    ),
  );
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.onHint,
    required this.onSolve,
    required this.onCheck,
    required this.boardSize,
    required this.difficulty,
    required this.includeBlankCells,
    required this.onBoardSizeChanged,
    required this.onDifficultyChanged,
    required this.onIncludeBlankCellsChanged,
    required this.onGenerate,
    required this.status,
  });

  final VoidCallback onHint;
  final VoidCallback onSolve;
  final VoidCallback onCheck;
  final int boardSize;
  final PuzzleDifficulty difficulty;
  final bool includeBlankCells;
  final ValueChanged<int> onBoardSizeChanged;
  final ValueChanged<PuzzleDifficulty> onDifficultyChanged;
  final ValueChanged<bool> onIncludeBlankCellsChanged;
  final VoidCallback onGenerate;
  final String status;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('数回', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        const Text('让所有线段组成一个闭环，并让每个数字格周围的线数相等。'),
        const SizedBox(height: 22),
        Text('新题设置', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: boardSize,
          decoration: const InputDecoration(
            labelText: '棋盘大小',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: const [
            DropdownMenuItem(value: 4, child: Text('4 × 4')),
            DropdownMenuItem(value: 5, child: Text('5 × 5')),
            DropdownMenuItem(value: 6, child: Text('6 × 6')),
          ],
          onChanged: (value) {
            if (value != null) onBoardSizeChanged(value);
          },
        ),
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
        FilledButton.icon(
          onPressed: onGenerate,
          icon: const Icon(Icons.casino_outlined),
          label: const Text('按此设置生成新题'),
        ),
        const Divider(height: 32),
        FilledButton.icon(
          onPressed: onHint,
          icon: const Icon(Icons.lightbulb_outline),
          label: const Text('提示'),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: onSolve,
          icon: const Icon(Icons.auto_fix_high),
          label: const Text('自动解题'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: onCheck,
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
    ),
  );
}

class _BoardPanel extends StatelessWidget {
  const _BoardPanel({
    required this.puzzle,
    required this.state,
    required this.highlights,
    required this.onGesture,
  });

  final SlitherlinkPuzzle puzzle;
  final SlitherlinkState state;
  final List<PuzzleTarget> highlights;
  final void Function(PuzzleTarget, PointerGesture) onGesture;

  @override
  Widget build(BuildContext context) => Center(
    child: AspectRatio(
      aspectRatio: 1,
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final geometry = _BoardGeometry(
              puzzle.topology,
              constraints.biggest,
            );
            return GestureDetector(
              onTapUp: (details) {
                final edge = geometry.hitEdge(details.localPosition);
                if (edge != null) {
                  onGesture(EdgeTarget(edge), PointerGesture.primaryTap);
                }
              },
              onSecondaryTapUp: (details) {
                final edge = geometry.hitEdge(details.localPosition);
                if (edge != null) {
                  onGesture(EdgeTarget(edge), PointerGesture.secondaryTap);
                }
              },
              child: CustomPaint(
                painter: _SlitherlinkPainter(
                  puzzle: puzzle,
                  state: state,
                  highlights: highlights,
                  geometry: geometry,
                ),
                child: const SizedBox.expand(),
              ),
            );
          },
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
      oldDelegate.state != state ||
      oldDelegate.highlights != highlights ||
      oldDelegate.geometry.size != geometry.size;
}
