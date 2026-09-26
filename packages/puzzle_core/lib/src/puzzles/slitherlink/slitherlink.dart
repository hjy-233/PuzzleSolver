import '../../interaction/puzzle_action.dart';
import '../../solver/solve_step.dart';
import '../../topology/grid_topology.dart';

enum SlitherlinkEdgeState { empty, line, crossed }

/// State owned only by Slitherlink. Other puzzles never see this enum or map.
final class SlitherlinkState {
  SlitherlinkState([Map<EdgeId, SlitherlinkEdgeState> edges = const {}])
    : _edges = Map.unmodifiable(edges);

  final Map<EdgeId, SlitherlinkEdgeState> _edges;

  SlitherlinkEdgeState stateOf(EdgeId edge) =>
      _edges[edge] ?? SlitherlinkEdgeState.empty;

  SlitherlinkState withEdge(EdgeId edge, SlitherlinkEdgeState state) {
    final edges = Map<EdgeId, SlitherlinkEdgeState>.from(_edges);
    if (state == SlitherlinkEdgeState.empty) {
      edges.remove(edge);
    } else {
      edges[edge] = state;
    }
    return SlitherlinkState(edges);
  }
}

sealed class SlitherlinkAction implements PuzzleAction {
  const SlitherlinkAction();
}

final class SetSlitherlinkEdge extends SlitherlinkAction {
  const SetSlitherlinkEdge(this.edge, this.state);

  final EdgeId edge;
  final SlitherlinkEdgeState state;
}

/// A small but real rule engine for an edge-first puzzle.
final class SlitherlinkPuzzle {
  SlitherlinkPuzzle({required this.topology, required Map<CellId, int> clues})
    : clues = Map.unmodifiable(clues) {
    for (final entry in clues.entries) {
      if (!topology.containsCell(entry.key)) {
        throw ArgumentError.value(
          entry.key,
          'clues',
          'Clue is outside the topology',
        );
      }
      if (entry.value < 0 || entry.value > 4) {
        throw ArgumentError.value(
          entry.value,
          'clues',
          'A Slitherlink clue must be 0 through 4',
        );
      }
    }
  }

  final GridTopology topology;
  final Map<CellId, int> clues;

  SlitherlinkState get initialState => SlitherlinkState();

  SlitherlinkState reduce(SlitherlinkState state, SlitherlinkAction action) {
    switch (action) {
      case SetSlitherlinkEdge(:final edge, state: final targetState):
        if (!topology.containsEdge(edge)) {
          throw ArgumentError.value(
            edge,
            'edge',
            'Action is outside the topology',
          );
        }
        return state.withEdge(edge, targetState);
    }
  }

  /// Maps a renderer gesture to this puzzle's own action without teaching the
  /// shared core what a line or cross means.
  SlitherlinkAction? actionFor(
    PuzzleTarget target,
    PointerGesture gesture,
    SlitherlinkState state,
  ) {
    if (target is! EdgeTarget) return null;
    final current = state.stateOf(target.edge);
    return switch (gesture) {
      PointerGesture.primaryTap => SetSlitherlinkEdge(
        target.edge,
        current == SlitherlinkEdgeState.line
            ? SlitherlinkEdgeState.empty
            : SlitherlinkEdgeState.line,
      ),
      PointerGesture.secondaryTap => SetSlitherlinkEdge(
        target.edge,
        current == SlitherlinkEdgeState.crossed
            ? SlitherlinkEdgeState.empty
            : SlitherlinkEdgeState.crossed,
      ),
      PointerGesture.doubleTap || PointerGesture.longPress => null,
    };
  }

  CheckResult check(SlitherlinkState state) {
    for (final entry in clues.entries) {
      final edges = topology.edgesAround(entry.key);
      final lines = edges
          .where((edge) => state.stateOf(edge) == SlitherlinkEdgeState.line)
          .length;
      final undecided = edges
          .where((edge) => state.stateOf(edge) == SlitherlinkEdgeState.empty)
          .length;
      if (lines > entry.value || lines + undecided < entry.value) {
        return const CheckResult(
          CheckStatus.invalid,
          messageKey: 'slitherlink.clueContradiction',
        );
      }
      if (lines != entry.value) {
        return const CheckResult(CheckStatus.incomplete);
      }
    }
    if (topology.allEdges.any(
      (edge) => state.stateOf(edge) == SlitherlinkEdgeState.empty,
    )) {
      return const CheckResult(CheckStatus.incomplete);
    }

    final lineEdges = topology.allEdges
        .where((edge) => state.stateOf(edge) == SlitherlinkEdgeState.line)
        .toSet();
    if (lineEdges.isEmpty) {
      return const CheckResult(
        CheckStatus.invalid,
        messageKey: 'slitherlink.noLoop',
      );
    }
    final vertices = <VertexId, List<EdgeId>>{};
    for (final edge in lineEdges) {
      for (final vertex in topology.verticesOf(edge)) {
        vertices.putIfAbsent(vertex, () => []).add(edge);
      }
    }
    if (vertices.values.any((edges) => edges.length != 2)) {
      return const CheckResult(
        CheckStatus.invalid,
        messageKey: 'slitherlink.openOrBranchingLine',
      );
    }
    if (!_isSingleLoop(lineEdges, vertices)) {
      return const CheckResult(
        CheckStatus.invalid,
        messageKey: 'slitherlink.multipleLoops',
      );
    }
    return const CheckResult(CheckStatus.solved);
  }

  bool _isSingleLoop(
    Set<EdgeId> lineEdges,
    Map<VertexId, List<EdgeId>> edgesAtVertex,
  ) {
    final visited = <EdgeId>{};
    final pending = <EdgeId>[lineEdges.first];
    while (pending.isNotEmpty) {
      final edge = pending.removeLast();
      if (!visited.add(edge)) {
        continue;
      }
      for (final vertex in topology.verticesOf(edge)) {
        pending.addAll(edgesAtVertex[vertex]!);
      }
    }
    return visited.length == lineEdges.length;
  }

  /// Returns the first certain local deduction, suitable for a hint timeline.
  SolveStep<SlitherlinkAction>? hint(SlitherlinkState state) {
    for (final entry in clues.entries) {
      final edges = topology.edgesAround(entry.key);
      final lines = edges
          .where((edge) => state.stateOf(edge) == SlitherlinkEdgeState.line)
          .length;
      final empty = edges
          .where((edge) => state.stateOf(edge) == SlitherlinkEdgeState.empty)
          .toList();
      if (empty.isEmpty) {
        continue;
      }
      if (lines == entry.value) {
        return SolveStep(
          ruleId: 'slitherlink.clueReached',
          highlights: [CellTarget(entry.key), ...empty.map(EdgeTarget.new)],
          actions: [
            for (final edge in empty)
              SetSlitherlinkEdge(edge, SlitherlinkEdgeState.crossed),
          ],
          arguments: {'clue': entry.value, 'lines': lines},
        );
      }
      if (lines + empty.length == entry.value) {
        return SolveStep(
          ruleId: 'slitherlink.remainingEdgesRequired',
          highlights: [CellTarget(entry.key), ...empty.map(EdgeTarget.new)],
          actions: [
            for (final edge in empty)
              SetSlitherlinkEdge(edge, SlitherlinkEdgeState.line),
          ],
          arguments: {'clue': entry.value, 'lines': lines},
        );
      }
    }
    return null;
  }
}
