///|
/// Identifiers are local to the sketch that created them.
pub struct PointId {
  index : Int32
} derive(Debug)

///|
pub extend PointId with @debug.Debug::{to_repr}

///|
pub struct LineId {
  index : Int32
} derive(Debug)

///|
pub extend LineId with @debug.Debug::{to_repr}

///|
pub struct CircleId {
  index : Int32
} derive(Debug)

///|
pub extend CircleId with @debug.Debug::{to_repr}

///|
pub struct ConstraintId {
  index : Int32
} derive(Debug)

///|
pub extend ConstraintId with @debug.Debug::{to_repr}

///|
pub fn ConstraintId::index(self : ConstraintId) -> Int32 {
  self.index
}

///|
pub(all) struct Point {
  x : Double
  y : Double
} derive(Debug)

///|
pub extend Point with @debug.Debug::{to_repr}

///|
priv struct Line {
  a : PointId
  b : PointId
}

///|
priv struct Circle {
  center : PointId
  radius : Double
}

///|
/// Angles are directed counterclockwise, in radians. Lines extend infinitely
/// for PointOnLine and Tangent. Distances use the caller's common length unit.
pub(all) enum Constraint {
  Fix(PointId, Double, Double)
  Coincident(PointId, PointId)
  Symmetric(PointId, PointId, PointId)
  Horizontal(LineId)
  Vertical(LineId)
  Distance(PointId, PointId, Double)
  DistanceX(PointId, PointId, Double)
  DistanceY(PointId, PointId, Double)
  Parallel(LineId, LineId)
  Perpendicular(LineId, LineId)
  Angle(LineId, LineId, Double)
  EqualLength(LineId, LineId)
  LengthRatio(LineId, LineId, Double)
  Midpoint(PointId, LineId)
  PointOnLine(PointId, LineId)
  DistanceToLine(PointId, LineId, Double)
  Radius(CircleId, Double)
  EqualRadius(CircleId, CircleId)
  Concentric(CircleId, CircleId)
  PointOnCircle(PointId, CircleId)
  Tangent(LineId, CircleId)
  ExternalTangent(CircleId, CircleId)
  InternalTangent(CircleId, CircleId)
} derive(Debug)

///|
pub extend Constraint with @debug.Debug::{to_repr}

///|
/// Geometry is modified only by explicit setters and apply(), never by solve().
pub struct Sketch {
  priv points : Array[Point]
  priv lines : Array[Line]
  priv circles : Array[Circle]
  priv constraints : Array[Constraint]
  priv enabled : Array[Bool]
}

///|
pub fn Sketch::new() -> Sketch {
  { points: [], lines: [], circles: [], constraints: [], enabled: [], }
}

///|
/// Nonfinite coordinates are rejected by solve().
pub fn Sketch::add_point(self : Sketch, x : Double, y : Double) -> PointId {
  let id : PointId = { index: self.points.length(), }
  self.points.push({ x, y, })
  id
}

///|
pub fn Sketch::add_line(self : Sketch, a : PointId, b : PointId) -> LineId {
  let id : LineId = { index: self.lines.length(), }
  self.lines.push({ a, b, })
  id
}

///|
/// Radius must be finite and strictly positive at solve time.
pub fn Sketch::add_circle(
  self : Sketch,
  center : PointId,
  radius : Double,
) -> CircleId {
  let id : CircleId = { index: self.circles.length(), }
  self.circles.push({ center, radius, })
  id
}

///|
pub fn Sketch::constrain(self : Sketch, c : Constraint) -> ConstraintId {
  let id : ConstraintId = { index: self.constraints.length(), }
  self.constraints.push(c)
  self.enabled.push(true)
  id
}

///|
pub fn Sketch::point(self : Sketch, id : PointId) -> Point? {
  self.points.get(id.index)
}

///|
pub fn Sketch::radius(self : Sketch, id : CircleId) -> Double? {
  self.circles.get(id.index).map(c => c.radius)
}

///|
/// Look up the original relation from a diagnostic's constraint identifier.
pub fn Sketch::constraint(self : Sketch, id : ConstraintId) -> Constraint? {
  self.constraints.get(id.index)
}

///|
/// Temporarily suppress a relation without changing any constraint identifiers.
pub fn Sketch::set_constraint_enabled(
  self : Sketch,
  id : ConstraintId,
  enabled : Bool,
) -> Bool {
  if id.index < 0 || id.index >= self.enabled.length() {
    false
  } else {
    self.enabled[id.index] = enabled
    true
  }
}

///|
pub fn Sketch::constraint_enabled(self : Sketch, id : ConstraintId) -> Bool? {
  self.enabled.get(id.index)
}

///|
/// Set a new initial guess, for example before resolving a dragged sketch.
pub fn Sketch::set_point(self : Sketch, id : PointId, p : Point) -> Bool {
  if id.index < 0 || id.index >= self.points.length() {
    false
  } else {
    self.points[id.index] = p
    true
  }
}

///|
/// Change the initial radius without replacing the circle or its constraints.
/// This does not fix the radius: use Radius for a driving dimension.
/// Like set_point(), values are validated at solve time.
pub fn Sketch::set_radius(
  self : Sketch,
  id : CircleId,
  radius : Double,
) -> Bool {
  if !self.valid_circle(id) {
    false
  } else {
    let c = self.circles[id.index]
    self.circles[id.index] = { center: c.center, radius, }
    true
  }
}

///|
/// Edit a dimension without rebuilding the sketch.
pub fn Sketch::set_constraint(
  self : Sketch,
  id : ConstraintId,
  c : Constraint,
) -> Bool {
  if id.index < 0 || id.index >= self.constraints.length() {
    false
  } else {
    self.constraints[id.index] = c
    true
  }
}

///|
fn finite(x : Double) -> Bool {
  !x.is_nan() && !x.is_inf()
}

///|
fn max_abs(values : Array[Double]) -> Double {
  let mut result = 0.0
  for x in values {
    result = dmax(result, x.abs())
  }
  result
}

///|
fn dmax(a : Double, b : Double) -> Double {
  if a > b {
    a
  } else {
    b
  }
}
