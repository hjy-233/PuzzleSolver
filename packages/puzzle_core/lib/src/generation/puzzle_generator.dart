/// Marker base class for puzzle-specific generation options.
///
/// The shared core intentionally does not force different puzzles to share
/// fields such as board size or difficulty. Each puzzle owns a concrete
/// options type that implements this interface.
abstract interface class PuzzleGenerationOptions {
  const PuzzleGenerationOptions();
}

/// Common contract for generators while preserving puzzle-owned options.
abstract interface class PuzzleGenerator<
  Result,
  Options extends PuzzleGenerationOptions
> {
  Result generate(Options options);
}
