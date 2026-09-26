import '../interaction/puzzle_action.dart';

/// A localized explanation is rendered from [ruleId] and [arguments] by the app.
/// The solver never returns unstructured prose as its source of truth.
final class SolveStep<A extends PuzzleAction> {
  const SolveStep({
    required this.ruleId,
    required this.highlights,
    required this.actions,
    this.arguments = const {},
  });

  final String ruleId;
  final List<PuzzleTarget> highlights;
  final List<A> actions;
  final Map<String, Object?> arguments;
}

enum CheckStatus { incomplete, solved, invalid }

final class CheckResult {
  const CheckResult(this.status, {this.messageKey});

  final CheckStatus status;
  final String? messageKey;
}
