import 'package:flutter/material.dart';

enum PuzzleShareChoice { page, puzzle, progress }

final class PuzzleTopBar extends StatelessWidget
    implements PreferredSizeWidget {
  const PuzzleTopBar({
    required this.mobile,
    required this.width,
    required this.puzzleName,
    required this.canUndo,
    required this.canRedo,
    required this.onShare,
    required this.onNewPuzzle,
    required this.onUndo,
    required this.onRedo,
    this.onOpenPuzzleDrawer,
    super.key,
  });

  final bool mobile;
  final double width;
  final String puzzleName;
  final bool canUndo;
  final bool canRedo;
  final ValueChanged<PuzzleShareChoice> onShare;
  final VoidCallback? onNewPuzzle;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback? onOpenPuzzleDrawer;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final showUndo = !mobile || width >= 360;
    final showRedo = !mobile || width >= 420;
    return AppBar(
      leading: mobile
          ? Builder(
              builder: (context) => IconButton(
                tooltip: '选择谜题',
                icon: const Icon(Icons.menu),
                onPressed:
                    onOpenPuzzleDrawer ?? Scaffold.of(context).openDrawer,
              ),
            )
          : null,
      title: Text(mobile ? puzzleName : 'PuzzleSolver'),
      actions: [
        PopupMenuButton<PuzzleShareChoice>(
          tooltip: '分享',
          icon: const Icon(Icons.share_outlined),
          onSelected: onShare,
          itemBuilder: (_) => [
            PopupMenuItem(
              value: PuzzleShareChoice.page,
              child: Text('仅分享$puzzleName页面'),
            ),
            const PopupMenuItem(
              value: PuzzleShareChoice.puzzle,
              child: Text('分享当前题目'),
            ),
            const PopupMenuItem(
              value: PuzzleShareChoice.progress,
              child: Text('分享题目和当前进度'),
            ),
          ],
        ),
        if (mobile)
          IconButton(
            tooltip: '新题',
            onPressed: onNewPuzzle,
            icon: const Icon(Icons.refresh),
          )
        else
          TextButton.icon(
            onPressed: onNewPuzzle,
            icon: const Icon(Icons.refresh),
            label: const Text('新题'),
          ),
        if (showUndo)
          mobile
              ? IconButton(
                  tooltip: '撤销',
                  onPressed: canUndo ? onUndo : null,
                  icon: const Icon(Icons.undo),
                )
              : TextButton.icon(
                  onPressed: canUndo ? onUndo : null,
                  icon: const Icon(Icons.undo),
                  label: const Text('撤销'),
                ),
        if (showRedo)
          mobile
              ? IconButton(
                  tooltip: '重做',
                  onPressed: canRedo ? onRedo : null,
                  icon: const Icon(Icons.redo),
                )
              : TextButton.icon(
                  onPressed: canRedo ? onRedo : null,
                  icon: const Icon(Icons.redo),
                  label: const Text('重做'),
                ),
        if (mobile && (!showUndo || !showRedo))
          PopupMenuButton<String>(
            tooltip: '更多操作',
            onSelected: (value) => value == 'undo' ? onUndo() : onRedo(),
            itemBuilder: (_) => [
              if (!showUndo)
                PopupMenuItem(
                  value: 'undo',
                  enabled: canUndo,
                  child: const Text('撤销'),
                ),
              if (!showRedo)
                PopupMenuItem(
                  value: 'redo',
                  enabled: canRedo,
                  child: const Text('重做'),
                ),
            ],
          ),
        const SizedBox(width: 8),
      ],
    );
  }
}

final class PuzzleStepItem {
  const PuzzleStepItem({required this.title, required this.description});

  final String title;
  final String description;
}

final class PuzzleLibrarySidebar extends StatelessWidget {
  const PuzzleLibrarySidebar({
    required this.puzzleName,
    required this.puzzleIcon,
    required this.sizeLabel,
    required this.otherPuzzleName,
    required this.otherPuzzleIcon,
    required this.onSelectOtherPuzzle,
    required this.steps,
    required this.selectedStepIndex,
    required this.onStepTap,
    required this.onClose,
    super.key,
  });

  final String puzzleName;
  final IconData puzzleIcon;
  final String sizeLabel;
  final String otherPuzzleName;
  final IconData otherPuzzleIcon;
  final VoidCallback onSelectOtherPuzzle;
  final List<PuzzleStepItem> steps;
  final int? selectedStepIndex;
  final ValueChanged<int> onStepTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFF14161D),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          title: const Text('谜题库'),
          trailing: IconButton(
            tooltip: '隐藏谜题栏',
            onPressed: onClose,
            icon: const Icon(Icons.close),
          ),
        ),
        ListTile(
          selected: true,
          leading: Icon(puzzleIcon),
          title: Text(puzzleName),
          subtitle: Text(sizeLabel),
        ),
        ListTile(
          leading: Icon(otherPuzzleIcon),
          title: Text(otherPuzzleName),
          onTap: onSelectOtherPuzzle,
        ),
        const Divider(),
        ListTile(title: const Text('推理步骤'), trailing: Text('${steps.length}')),
        Expanded(
          child: steps.isEmpty
              ? const Center(child: Text('还没有提示步骤'))
              : ListView.builder(
                  itemCount: steps.length,
                  itemBuilder: (_, index) => ListTile(
                    selected: selectedStepIndex == index,
                    leading: CircleAvatar(
                      radius: 12,
                      child: Text('${index + 1}'),
                    ),
                    title: Text(steps[index].title),
                    subtitle: Text(
                      steps[index].description,
                      maxLines: 2,
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

final class PuzzleMobileStepsPanel extends StatelessWidget {
  const PuzzleMobileStepsPanel({
    required this.steps,
    required this.selectedStepIndex,
    required this.onStepTap,
    required this.onHide,
    required this.status,
    super.key,
  });

  final List<PuzzleStepItem> steps;
  final int? selectedStepIndex;
  final ValueChanged<int> onStepTap;
  final VoidCallback onHide;
  final String status;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFF14161D),
    child: Column(
      children: [
        ListTile(
          dense: true,
          title: const Text('推理步骤'),
          subtitle: Text('${steps.length} 步'),
          trailing: IconButton(
            tooltip: '隐藏推理步骤',
            onPressed: onHide,
            icon: const Icon(Icons.expand_more),
          ),
        ),
        if (selectedStepIndex case final index?
            when index >= 0 && index < steps.length)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              steps[index].description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        Expanded(
          child: steps.isEmpty
              ? Center(child: Text(status))
              : ListView.builder(
                  itemCount: steps.length,
                  itemBuilder: (_, index) => ListTile(
                    dense: true,
                    selected: selectedStepIndex == index,
                    leading: CircleAvatar(
                      radius: 12,
                      child: Text('${index + 1}'),
                    ),
                    title: Text(steps[index].title),
                    onTap: () => onStepTap(index),
                  ),
                ),
        ),
      ],
    ),
  );
}

final class PuzzleControlsPanel extends StatelessWidget {
  const PuzzleControlsPanel({
    required this.title,
    required this.description,
    required this.child,
    this.onClose,
    this.closeTooltip = '隐藏设置栏',
    super.key,
  });

  final String title;
  final String description;
  final Widget child;
  final VoidCallback? onClose;
  final String closeTooltip;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            if (onClose != null)
              IconButton(
                tooltip: closeTooltip,
                onPressed: onClose,
                icon: const Icon(Icons.close),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(description),
        const SizedBox(height: 22),
        child,
      ],
    ),
  );
}

final class PuzzleBoardController {
  PuzzleBoardController() : transformation = TransformationController();

  final TransformationController transformation;

  double get scale => transformation.value.getMaxScaleOnAxis();

  void panBy(Offset delta) {
    final matrix = transformation.value.clone();
    matrix.storage[12] += delta.dx;
    matrix.storage[13] += delta.dy;
    transformation.value = matrix;
  }

  void zoomCentered(
    Size viewport,
    double factor, {
    double min = .7,
    double max = 5,
  }) {
    final nextScale = (scale * factor).clamp(min, max);
    final appliedFactor = nextScale / scale;
    transformation.value = transformation.value.clone()
      ..translateByDouble(
        viewport.width * (1 - appliedFactor) / 2,
        viewport.height * (1 - appliedFactor) / 2,
        0,
        1,
      )
      ..scaleByDouble(appliedFactor, appliedFactor, 1, 1);
  }

  void zoomAt(
    Offset oldFocalPoint,
    Offset newFocalPoint,
    double factor, {
    double min = .7,
    double max = 5,
  }) {
    final nextScale = (scale * factor).clamp(min, max);
    final sceneAnchor = transformation.toScene(oldFocalPoint);
    transformation.value = Matrix4.identity()
      ..translateByDouble(
        newFocalPoint.dx - sceneAnchor.dx * nextScale,
        newFocalPoint.dy - sceneAnchor.dy * nextScale,
        0,
        1,
      )
      ..scaleByDouble(nextScale, nextScale, 1, 1);
  }

  void reset() => transformation.value = Matrix4.identity();

  void dispose() => transformation.dispose();
}

final class PuzzleBoardTools extends StatelessWidget {
  const PuzzleBoardTools({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
    this.onShowPuzzleSidebar,
    this.onShowControlsSidebar,
    super.key,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;
  final VoidCallback? onShowPuzzleSidebar;
  final VoidCallback? onShowControlsSidebar;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (onShowPuzzleSidebar != null)
        _button(Icons.menu_open, '显示谜题栏', onShowPuzzleSidebar!),
      if (onShowControlsSidebar != null)
        _button(Icons.tune, '显示设置栏', onShowControlsSidebar!),
      _button(Icons.add, '放大棋盘', onZoomIn),
      _button(Icons.remove, '缩小棋盘', onZoomOut),
      _button(Icons.fit_screen_outlined, '重置棋盘缩放', onReset),
    ],
  );

  Widget _button(IconData icon, String tooltip, VoidCallback onPressed) =>
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: IconButton.filledTonal(
          tooltip: tooltip,
          onPressed: onPressed,
          icon: Icon(icon),
          visualDensity: VisualDensity.compact,
        ),
      );
}

final class PuzzleActionItem {
  const PuzzleActionItem({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
}

final class PuzzleMobileActionBar extends StatelessWidget {
  const PuzzleMobileActionBar({required this.actions, super.key});

  final List<PuzzleActionItem> actions;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFF161821),
    child: SizedBox(
      height: 68,
      child: Row(
        children: [
          for (final action in actions)
            Expanded(
              child: Tooltip(
                message: action.label,
                child: InkWell(
                  onTap: action.onPressed,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        action.icon,
                        size: 23,
                        color: action.onPressed == null
                            ? null
                            : const Color(0xFFB7C5FF),
                      ),
                      const SizedBox(height: 2),
                      Text(action.label, style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

Future<void> showPuzzleSettingsSheet(
  BuildContext context,
  Widget Function(BuildContext context, VoidCallback refresh) builder,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (context) => StatefulBuilder(
    builder: (context, setSheetState) => FractionallySizedBox(
      heightFactor: .9,
      child: builder(context, () => setSheetState(() {})),
    ),
  ),
);

final class PuzzleWorkspace extends StatelessWidget {
  const PuzzleWorkspace({
    required this.board,
    required this.leftSidebar,
    required this.rightSidebar,
    required this.mobileControls,
    required this.mobileSteps,
    required this.showLeftSidebar,
    required this.showRightSidebar,
    required this.showMobileSteps,
    required this.onShowMobileSteps,
    super.key,
  });

  final Widget board;
  final Widget leftSidebar;
  final Widget rightSidebar;
  final Widget mobileControls;
  final Widget mobileSteps;
  final bool showLeftSidebar;
  final bool showRightSidebar;
  final bool showMobileSteps;
  final VoidCallback onShowMobileSteps;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 920) {
        return Column(
          children: [
            Expanded(flex: 6, child: board),
            mobileControls,
            const Divider(height: 1),
            if (showMobileSteps)
              Expanded(flex: 5, child: mobileSteps)
            else
              SizedBox(
                height: 40,
                child: TextButton.icon(
                  onPressed: onShowMobileSteps,
                  icon: const Icon(Icons.expand_less),
                  label: const Text('显示推理步骤'),
                ),
              ),
          ],
        );
      }
      return Row(
        children: [
          if (showLeftSidebar) ...[
            SizedBox(width: 250, child: leftSidebar),
            const VerticalDivider(width: 1),
          ],
          Expanded(child: board),
          if (showRightSidebar) ...[
            const VerticalDivider(width: 1),
            SizedBox(width: 310, child: rightSidebar),
          ],
        ],
      );
    },
  );
}
