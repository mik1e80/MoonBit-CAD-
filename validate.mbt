///|
fn Sketch::valid_point(self : Sketch, id : PointId) -> Bool {
  physical_equal(self.owner, id.owner) &&
  id.index >= 0 &&
  id.index < self.points.length()
}

///|
fn Sketch::valid_line(self : Sketch, id : LineId) -> Bool {
  physical_equal(self.owner, id.owner) &&
  id.index >= 0 &&
  id.index < self.lines.length()
}

///|
fn Sketch::valid_circle(self : Sketch, id : CircleId) -> Bool {
  physical_equal(self.owner, id.owner) &&
  id.index >= 0 &&
  id.index < self.circles.length()
}

///|
fn Sketch::constraint_slot(self : Sketch, id : ConstraintId) -> Int32? {
  if !physical_equal(self.owner, id.owner) || id.index < 0 {
    return None
  }
  for slot, stored in self.constraint_ids {
    if stored.index == id.index {
      return Some(slot)
    }
  }
  None
}

///|
fn bounded(x : Double) -> Bool {
  finite(x) && x.abs() <= 1.0e100
}

///|
fn Sketch::constraint_has_foreign_handle(self : Sketch, c : Constraint) -> Bool {
  let point = (p : PointId) => physical_equal(self.owner, p.owner)
  let line = (l : LineId) => physical_equal(self.owner, l.owner)
  let circle = (c : CircleId) => physical_equal(self.owner, c.owner)
  let owned = match c {
    Fix(p, _, _) => point(p)
    Coincident(a, b)
    | Distance(a, b, _)
    | DistanceX(a, b, _)
    | DistanceY(a, b, _) => point(a) && point(b)
    Symmetric(a, b, center) => point(a) && point(b) && point(center)
    Mirror(a, b, axis) => point(a) && point(b) && line(axis)
    Horizontal(l) | Vertical(l) => line(l)
    Parallel(a, b)
    | Perpendicular(a, b)
    | EqualLength(a, b)
    | LengthRatio(a, b, _)
    | Angle(a, b, _) => line(a) && line(b)
    Midpoint(p, l) | PointOnLine(p, l) | DistanceToLine(p, l, _) =>
      point(p) && line(l)
    Radius(c, _) => circle(c)
    EqualRadius(a, b)
    | Concentric(a, b)
    | ExternalTangent(a, b)
    | InternalTangent(a, b) => circle(a) && circle(b)
    PointOnCircle(p, c) => point(p) && circle(c)
    Tangent(l, c) => line(l) && circle(c)
  }
  !owned
}

///|
fn Sketch::validate(self : Sketch) -> Result[Unit, SketchError] {
  if self.points.length() * 2 + self.circles.length() > 256 ||
    self.constraints.length() > 512 ||
    self.lines.length() > 512 {
    return Err(ResourceLimit)
  }
  for i, p in self.points {
    if !bounded(p.x) || !bounded(p.y) {
      return Err(
        InvalidGeometry(
          "Point at index \{i}: coordinates must be finite and within +/-1e100",
        ),
      )
    }
  }
  for i, l in self.lines {
    if !physical_equal(self.owner, l.a.owner) ||
      !physical_equal(self.owner, l.b.owner) {
      return Err(ForeignHandle)
    }
    if !self.valid_point(l.a) || !self.valid_point(l.b) {
      return Err(
        InvalidGeometry("Line at index \{i}: references a missing point"),
      )
    }
    let a = self.points[l.a.index]
    let b = self.points[l.b.index]
    if a.x == b.x && a.y == b.y {
      return Err(DegenerateLine(self.line_id(i)))
    }
  }
  for i, c in self.circles {
    if !physical_equal(self.owner, c.center.owner) {
      return Err(ForeignHandle)
    }
    if !self.valid_point(c.center) {
      return Err(
        InvalidGeometry("Circle at index \{i}: references a missing center"),
      )
    }
    if !bounded(c.radius) || c.radius <= 0.0 {
      return Err(InvalidRadius(self.circle_id(i)))
    }
  }
  for i, c in self.constraints {
    if !self.enabled[i] {
      continue
    }
    if self.constraint_has_foreign_handle(c) {
      return Err(ForeignHandle)
    }
    let ok = match c {
      Fix(p, x, y) => self.valid_point(p) && bounded(x) && bounded(y)
      Coincident(a, b) => self.valid_point(a) && self.valid_point(b)
      Symmetric(a, b, center) =>
        self.valid_point(a) && self.valid_point(b) && self.valid_point(center)
      Mirror(a, b, axis) =>
        self.valid_point(a) && self.valid_point(b) && self.valid_line(axis)
      Horizontal(l) | Vertical(l) => self.valid_line(l)
      Distance(a, b, d) =>
        self.valid_point(a) && self.valid_point(b) && bounded(d) && d >= 0.0
      DistanceX(a, b, d) | DistanceY(a, b, d) =>
        self.valid_point(a) && self.valid_point(b) && bounded(d)
      Parallel(a, b) | Perpendicular(a, b) | EqualLength(a, b) =>
        self.valid_line(a) && self.valid_line(b)
      LengthRatio(a, b, ratio) =>
        self.valid_line(a) &&
        self.valid_line(b) &&
        finite(ratio) &&
        ratio > 0.0 &&
        ratio <= 1.0e12
      Angle(a, b, t) =>
        self.valid_line(a) &&
        self.valid_line(b) &&
        finite(t) &&
        t.abs() <= 2.0 * @math.PI
      Midpoint(p, l) | PointOnLine(p, l) =>
        self.valid_point(p) && self.valid_line(l)
      DistanceToLine(p, l, d) =>
        self.valid_point(p) && self.valid_line(l) && bounded(d)
      Radius(c, r) => self.valid_circle(c) && bounded(r) && r > 0.0
      EqualRadius(a, b)
      | Concentric(a, b)
      | ExternalTangent(a, b)
      | InternalTangent(a, b) => self.valid_circle(a) && self.valid_circle(b)
      PointOnCircle(p, c) => self.valid_point(p) && self.valid_circle(c)
      Tangent(l, c) => self.valid_line(l) && self.valid_circle(c)
    }
    if !ok {
      return Err(InvalidConstraint(self.constraint_ids[i]))
    }
  }
  Ok(())
}

///|
priv struct Frame {
  x : Double
  y : Double
  scale : Double
}

///|
/// Translation and a uniform length scale keep typical coordinates near unity.
fn Sketch::frame(self : Sketch) -> Frame {
  let origin = self.points.get(0).unwrap_or({ x: 0.0, y: 0.0, })
  let mut scale = 0.0
  for p in self.points {
    scale = dmax(scale, dmax((p.x - origin.x).abs(), (p.y - origin.y).abs()))
  }
  for c in self.circles {
    scale = dmax(scale, c.radius)
  }
  for i, c in self.constraints {
    if !self.enabled[i] {
      continue
    }
    match c {
      Fix(_, x, y) => {
        scale = dmax(scale, (x - origin.x).abs())
        scale = dmax(scale, (y - origin.y).abs())
      }
      Distance(_, _, d)
      | DistanceX(_, _, d)
      | DistanceY(_, _, d)
      | DistanceToLine(_, _, d)
      | Radius(_, d) => scale = dmax(scale, d.abs())
      _ => ()
    }
  }
  { x: origin.x, y: origin.y, scale: if scale > 0.0 { scale } else { 1.0 }, }
}

///|
fn Sketch::parameters(self : Sketch, frame : Frame) -> Array[Double] {
  let out = []
  for p in self.points {
    out.push((p.x - frame.x) / frame.scale)
    out.push((p.y - frame.y) / frame.scale)
  }
  for c in self.circles {
    out.push(c.radius / frame.scale)
  }
  out
}
