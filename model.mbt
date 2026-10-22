///|
/// Identifiers are local to the sketch that created them.
pub struct PointId {
  index : Int32
  priv owner : Array[Unit]
} derive(Debug)

///|
pub extend PointId with @debug.Debug::{to_repr}

///|
pub struct LineId {
  index : Int32
  priv owner : Array[Unit]
} derive(Debug)

///|
pub extend LineId with @debug.Debug::{to_repr}

///|
pub struct CircleId {
  index : Int32
  priv owner : Array[Unit]
} derive(Debug)

///|
pub extend CircleId with @debug.Debug::{to_repr}

///|
pub struct ConstraintId {
  index : Int32
  priv owner : Array[Unit]
} derive(Debug)

///|
pub extend ConstraintId with @debug.Debug::{to_repr}

///|
/// Stable creation index, not a live-array offset after constraint removals.
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
  /// The two points are reflections across an infinite line, in either direction.
  Mirror(PointId, PointId, LineId)
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
  priv owner : Array[Unit]
  priv points : Array[Point]
  priv lines : Array[Line]
  priv circles : Array[Circle]
  priv constraints : Array[Constraint]
  priv enabled : Array[Bool]
  priv constraint_ids : Array[ConstraintId]
  priv next_constraint : Array[Int32]
}

///|
pub fn Sketch::new() -> Sketch {
  {
    owner: [()],
    points: [],
    lines: [],
    circles: [],
    constraints: [],
    enabled: [],
    constraint_ids: [],
    next_constraint: [0],
  }
}

///|
/// Mutable array identity is a runtime-local token; it is never serialized.
fn Sketch::point_id(self : Sketch, index : Int32) -> PointId {
  { index, owner: self.owner, }
}

///|
fn Sketch::line_id(self : Sketch, index : Int32) -> LineId {
  { index, owner: self.owner, }
}

///|
fn Sketch::circle_id(self : Sketch, index : Int32) -> CircleId {
  { index, owner: self.owner, }
}

///|
fn Sketch::constraint_id(self : Sketch, index : Int32) -> ConstraintId {
  { index, owner: self.owner, }
}

///|
/// Nonfinite coordinates are rejected by solve().
pub fn Sketch::add_point(self : Sketch, x : Double, y : Double) -> PointId {
  let id = self.point_id(self.points.length())
  self.points.push({ x, y, })
  id
}

///|
pub fn Sketch::add_line(self : Sketch, a : PointId, b : PointId) -> LineId {
  let id = self.line_id(self.lines.length())
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
  let id = self.circle_id(self.circles.length())
  self.circles.push({ center, radius, })
  id
}

///|
pub fn Sketch::constrain(self : Sketch, c : Constraint) -> ConstraintId {
  // IDs never alias a removed relation, even after compacting the live arrays.
  let index = self.next_constraint[0]
  if index == 2147483647 {
    abort("Constraint identifier space exhausted")
  }
  let id = self.constraint_id(index)
  self.next_constraint[0] = index + 1
  self.constraints.push(c)
  self.enabled.push(true)
  self.constraint_ids.push(id)
  id
}

///|
pub fn Sketch::point(self : Sketch, id : PointId) -> Point? {
  if self.valid_point(id) {
    self.points.get(id.index)
  } else {
    None
  }
}

///|
pub fn Sketch::radius(self : Sketch, id : CircleId) -> Double? {
  if self.valid_circle(id) {
    self.circles.get(id.index).map(c => c.radius)
  } else {
    None
  }
}

///|
/// Look up a live relation. Removed IDs return None, including old diagnostics.
pub fn Sketch::constraint(self : Sketch, id : ConstraintId) -> Constraint? {
  match self.constraint_slot(id) {
    Some(slot) => self.constraints.get(slot)
    None => None
  }
}

///|
/// Temporarily suppress a relation without changing any constraint identifiers.
pub fn Sketch::set_constraint_enabled(
  self : Sketch,
  id : ConstraintId,
  enabled : Bool,
) -> Bool {
  match self.constraint_slot(id) {
    None => false
    Some(slot) => {
      self.enabled[slot] = enabled
      true
    }
  }
}

///|
pub fn Sketch::constraint_enabled(self : Sketch, id : ConstraintId) -> Bool? {
  match self.constraint_slot(id) {
    Some(slot) => self.enabled.get(slot)
    None => None
  }
}

///|
/// Permanently remove a relation without changing geometry or other handles.
/// Removed/unknown/foreign IDs return false and can never be re-enabled.
/// Old solve reports remain snapshots; new reports omit this relation.
pub fn Sketch::remove_constraint(self : Sketch, id : ConstraintId) -> Bool {
  match self.constraint_slot(id) {
    None => false
    Some(slot) => {
      self.constraints.remove(slot) |> ignore
      self.enabled.remove(slot) |> ignore
      self.constraint_ids.remove(slot) |> ignore
      true
    }
  }
}

///|
/// Set a new initial guess, for example before resolving a dragged sketch.
pub fn Sketch::set_point(self : Sketch, id : PointId, p : Point) -> Bool {
  if !self.valid_point(id) {
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
  match self.constraint_slot(id) {
    None => false
    Some(slot) => {
      self.constraints[slot] = c
      true
    }
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
