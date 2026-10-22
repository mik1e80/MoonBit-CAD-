///|
/// Recoverable input, resource or numerical errors. Nonconvergence is reported
/// by SolveStatus inside Ok(Solution), rather than by this enum.
pub(all) enum SketchError {
  InvalidGeometry(String)
  InvalidConstraint(ConstraintId)
  ForeignHandle
  DegenerateLine(LineId)
  InvalidRadius(CircleId)
  ResourceLimit
  InvalidOptions(String)
  NumericalFailure(String)
} derive(Debug)

///|
pub extend SketchError with @debug.Debug::{to_repr}

///|
/// Human-readable context for logs. Match the variants for programmatic handling;
/// message wording is not a stable machine-readable interface.
pub fn SketchError::message(self : SketchError) -> String {
  match self {
    InvalidGeometry(message)
    | InvalidOptions(message)
    | NumericalFailure(message) => message
    InvalidConstraint(id) =>
      "Invalid constraint at index \{id.index}: bad reference, dimension or geometry domain"
    ForeignHandle => "Handle belongs to another sketch"
    DegenerateLine(id) =>
      "Line at index \{id.index}: zero-length or too short relative to sketch scale"
    InvalidRadius(id) =>
      "Circle at index \{id.index}: radius must be finite, positive and nondegenerate relative to sketch scale"
    ResourceLimit =>
      "Small-sketch limit: at most 256 variables, 512 lines, and 512 constraints"
  }
}
