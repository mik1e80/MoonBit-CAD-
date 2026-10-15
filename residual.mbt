///|
priv struct Row {
  jet : Jet
  constraint : Int32
  angular : Bool
}

///|
fn point_jets(p : PointId, vars : Array[Jet]) -> (Jet, Jet) {
  (vars[p.index * 2], vars[p.index * 2 + 1])
}

///|
fn Sketch::line_jets(
  self : Sketch,
  l : LineId,
  vars : Array[Jet],
) -> (Jet, Jet) {
  let line = self.lines[l.index]
  let (ax, ay) = point_jets(line.a, vars)
  let (bx, by) = point_jets(line.b, vars)
  (bx.minus(ax), by.minus(ay))
}

///|
fn Sketch::circle_jets(
  self : Sketch,
  c : CircleId,
  vars : Array[Jet],
) -> (Jet, Jet, Jet) {
  let (x, y) = point_jets(self.circles[c.index].center, vars)
  (x, y, vars[self.points.length() * 2 + c.index])
}

///|
fn push_rows(
  out : Array[Row],
  jets : Array[Jet],
  id : Int32,
  angular : Bool,
) -> Unit {
  for jet in jets {
    out.push({ jet, constraint: id, angular, })
  }
}

///|
/// The returned residuals use normalized length units (or radians / unitless
/// direction error for angular constraints). Tolerance weighting happens later.
fn Sketch::evaluate(
  self : Sketch,
  x : Array[Double],
  frame : Frame,
) -> Result[Array[Row], String] {
  if x.any(v => !finite(v)) {
    return Err("Nonfinite parameter during evaluation")
  }
  for i = self.points.length() * 2; i < x.length(); i = i + 1 {
    if x[i] <= 1.0e-14 {
      let circle = i - self.points.length() * 2
      return Err(
        "Circle at index \{circle}: radius approached zero relative to sketch scale",
      )
    }
  }
  let vars = Array::makei(x.length(), i => variable(x[i], i, x.length()))
  for i = 0; i < self.lines.length(); i = i + 1 {
    let (dx, dy) = self.line_jets({ index: i, }, vars)
    if @math.hypot(dx.v, dy.v) <= 1.0e-12 {
      return Err(
        "Line at index \{i}: too short relative to sketch scale; use a nondegenerate initial guess",
      )
    }
  }
  let out = []
  for i, c in self.constraints {
    if !self.enabled[i] {
      continue
    }
    let mut angular = false
    let jets = match c {
      Fix(p, x, y) => {
        let (px, py) = point_jets(p, vars)
        [
          px.offset(-(x - frame.x) / frame.scale),
          py.offset(-(y - frame.y) / frame.scale),
        ]
      }
      Coincident(a, b) => {
        let (ax, ay) = point_jets(a, vars)
        let (bx, by) = point_jets(b, vars)
        [bx.minus(ax), by.minus(ay)]
      }
      Horizontal(l) => {
        let (_, dy) = self.line_jets(l, vars)
        [dy]
      }
      Vertical(l) => {
        let (dx, _) = self.line_jets(l, vars)
        [dx]
      }
      Distance(a, b, d) => {
        let (ax, ay) = point_jets(a, vars)
        let (bx, by) = point_jets(b, vars)
        if d == 0.0 {
          [bx.minus(ax), by.minus(ay)]
        } else {
          [jet_norm(bx.minus(ax), by.minus(ay)).offset(-d / frame.scale)]
        }
      }
      DistanceX(a, b, d) => {
        let (ax, _) = point_jets(a, vars)
        let (bx, _) = point_jets(b, vars)
        [bx.minus(ax).offset(-d / frame.scale)]
      }
      DistanceY(a, b, d) => {
        let (_, ay) = point_jets(a, vars)
        let (_, by) = point_jets(b, vars)
        [by.minus(ay).offset(-d / frame.scale)]
      }
      Parallel(a, b) | Perpendicular(a, b) | Angle(a, b, _) => {
        angular = true
        let (ax, ay) = self.line_jets(a, vars)
        let (bx, by) = self.line_jets(b, vars)
        let na = jet_norm(ax, ay)
        let nb = jet_norm(bx, by)
        let ax = ax.divide(na)
        let ay = ay.divide(na)
        let bx = bx.divide(nb)
        let by = by.divide(nb)
        let cross = jet_cross(ax, ay, bx, by)
        let dot = jet_dot(ax, ay, bx, by)
        match c {
          Parallel(_, _) => [cross]
          Perpendicular(_, _) => [dot]
          Angle(_, _, t) => {
            // Rotate the unit pair by -t before atan2: principal wrapped error.
            let y = cross.scale(@math.cos(t)).minus(dot.scale(@math.sin(t)))
            let x = dot.scale(@math.cos(t)).plus(cross.scale(@math.sin(t)))
            [jet_angle(y, x)]
          }
          _ => []
        }
      }
      EqualLength(a, b) => {
        let (ax, ay) = self.line_jets(a, vars)
        let (bx, by) = self.line_jets(b, vars)
        [jet_norm(ax, ay).minus(jet_norm(bx, by))]
      }
      Midpoint(p, l) => {
        let (px, py) = point_jets(p, vars)
        let line = self.lines[l.index]
        let (ax, ay) = point_jets(line.a, vars)
        let (bx, by) = point_jets(line.b, vars)
        [px.minus(ax.plus(bx).scale(0.5)), py.minus(ay.plus(by).scale(0.5))]
      }
      PointOnLine(p, l) => {
        let (px, py) = point_jets(p, vars)
        let (ax, ay) = point_jets(self.lines[l.index].a, vars)
        let (dx, dy) = self.line_jets(l, vars)
        [jet_cross(dx, dy, px.minus(ax), py.minus(ay)).divide(jet_norm(dx, dy))]
      }
      Radius(c, r) => {
        let (_, _, radius) = self.circle_jets(c, vars)
        [radius.offset(-r / frame.scale)]
      }
      EqualRadius(a, b) => {
        let (_, _, ar) = self.circle_jets(a, vars)
        let (_, _, br) = self.circle_jets(b, vars)
        [ar.minus(br)]
      }
      Concentric(a, b) => {
        let (ax, ay, _) = self.circle_jets(a, vars)
        let (bx, by, _) = self.circle_jets(b, vars)
        [bx.minus(ax), by.minus(ay)]
      }
      PointOnCircle(p, c) => {
        let (px, py) = point_jets(p, vars)
        let (cx, cy, r) = self.circle_jets(c, vars)
        [jet_norm(px.minus(cx), py.minus(cy)).minus(r)]
      }
      Tangent(l, c) => {
        let (cx, cy, r) = self.circle_jets(c, vars)
        let (ax, ay) = point_jets(self.lines[l.index].a, vars)
        let (dx, dy) = self.line_jets(l, vars)
        let distance = jet_cross(dx, dy, cx.minus(ax), cy.minus(ay)).divide(
          jet_norm(dx, dy),
        )
        let sign = if distance.v < 0.0 { -1.0 } else { 1.0 }
        [distance.scale(sign).minus(r)]
      }
      ExternalTangent(a, b) => {
        let (ax, ay, ar) = self.circle_jets(a, vars)
        let (bx, by, br) = self.circle_jets(b, vars)
        [jet_norm(bx.minus(ax), by.minus(ay)).minus(ar.plus(br))]
      }
    }
    push_rows(out, jets, i, angular)
  }
  for row in out {
    if !finite(row.jet.v) || row.jet.d.any(v => !finite(v)) {
      return Err(
        "Constraint at index \{row.constraint}: nonfinite residual or derivative",
      )
    }
  }
  Ok(out)
}
