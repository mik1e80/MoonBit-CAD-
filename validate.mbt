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
fn Sketch::validate(self : Sketch) -> Result[Unit, String] {
  if self.points.length() * 2 + self.circles.length() > 256 ||
    self.constraints.length() > 512 ||
    self.lines.length() > 512 {
    return Err(
      "Small-sketch limit: at most 256 variables, 512 lines, and 512 constraints",
    )
  }
  for i, p in self.points {
    if !bounded(p.x) || !bounded(p.y) {
      return Err(
        "Point at index \{i}: coordinates must be finite and within +/-1e100",
      )
    }
  }
  for i, l in self.lines {
    if !self.valid_point(l.a) || !self.valid_point(l.b) {
      return Err("Line at index \{i}: references a missing point")
    }
    let a = self.points[l.a.index]
    let b = self.points[l.b.index]
    if a.x == b.x && a.y == b.y {
      return Err(
        "Line at index \{i}: zero-length initial line; provide distinct endpoints",
      )
    }
  }
  for i, c in self.circles {
    if !self.valid_point(c.center) || !bounded(c.radius) || c.radius <= 0.0 {
      return Err(
        "Circle at index \{i}: needs an existing center and a finite positive radius",
      )
    }
  }
  for i, c in self.constraints {
    if !self.enabled[i] {
      continue
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
      let id = self.constraint_ids[i].index
      return Err(
        "Invalid constraint at index \{id}: bad reference or dimension",
      )
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
