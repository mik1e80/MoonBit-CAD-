///|
fn solved(
  s : Sketch,
  options~ : SolveOptions = SolveOptions::default(),
) -> Solution raise {
  let result = match s.solve(options~) {
    Ok(r) => r
    Err(e) => fail(e.message())
  }
  if !result.report.is_satisfied() {
    fail("Did not solve: \{result.report.to_repr()}")
  }
  assert_true(result.report.max_tolerance_ratio <= 1.0)
  result
}

///|
fn near(a : Double, b : Double, tol~ : Double = 2.0e-6) -> Unit raise {
  assert_true((a - b).abs() <= tol, msg="\{a} != \{b}")
}

///|
fn sp(s : Solution, p : PointId) -> Point {
  s.point(p).unwrap()
}

///|
fn distance(a : Point, b : Point) -> Double {
  @math.hypot(a.x - b.x, a.y - b.y)
}

///|
test "empty and unconstrained sketches retain all degrees of freedom" {
  let empty = solved(Sketch::new())
  assert_eq(empty.report.local_dof, 0)
  let s = Sketch::new()
  let p = s.add_point(2.0, 3.0)
  let r = solved(s)
  assert_eq(r.report.local_dof, 2)
  near(sp(r, p).x, 2.0)
  near(sp(r, p).y, 3.0)
}

///|
test "rectangle solved from several perturbed guesses and scales" {
  for scale in [1.0e-6, 1.0, 1.0e6] {
    for noise in [-0.4, 0.2, 0.6] {
      let ox = 1200.0 * scale
      let oy = -700.0 * scale
      let s = Sketch::new()
      let a = s.add_point(ox + noise * scale, oy + 0.1 * scale)
      let b = s.add_point(ox + (9.0 + noise) * scale, oy - 0.3 * scale)
      let c = s.add_point(ox + 11.0 * scale, oy + (5.0 + noise) * scale)
      let d = s.add_point(ox - 0.5 * scale, oy + 6.0 * scale)
      let ab = s.add_line(a, b)
      let bc = s.add_line(b, c)
      let cd = s.add_line(c, d)
      let da = s.add_line(d, a)
      s.constrain(Fix(a, ox, oy)) |> ignore
      for l in [ab, cd] {
        s.constrain(Horizontal(l)) |> ignore
      }
      for l in [bc, da] {
        s.constrain(Vertical(l)) |> ignore
      }
      s.constrain(DistanceX(a, b, 10.0 * scale)) |> ignore
      s.constrain(DistanceY(b, c, 6.0 * scale)) |> ignore
      let r = solved(s, options={
        ..SolveOptions::default(),
        length_tolerance: 1.0e-8 * scale,
      })
      assert_eq(r.report.local_dof, 0)
      near(sp(r, a).x, ox, tol=2.0e-8 * scale)
      near(sp(r, a).y, oy, tol=2.0e-8 * scale)
      near(sp(r, b).x, ox + 10.0 * scale, tol=2.0e-8 * scale)
      near(sp(r, b).y, oy, tol=2.0e-8 * scale)
      near(sp(r, c).x, ox + 10.0 * scale, tol=2.0e-8 * scale)
      near(sp(r, c).y, oy + 6.0 * scale, tol=5.0e-8 * scale)
      near(sp(r, d).x, ox, tol=2.0e-8 * scale)
      near(sp(r, d).y, oy + 6.0 * scale, tol=5.0e-8 * scale)
      // solve() does not mutate the original geometry.
      near(s.point(a).unwrap().x, ox + noise * scale, tol=1.0e-12 * scale)
    }
  }
}

///|
test "3-4-5 triangle has analytic coordinates and rigid body freedom" {
  let s = Sketch::new()
  let a = s.add_point(0.2, -0.1)
  let b = s.add_point(4.5, 0.3)
  let c = s.add_point(2.2, 2.5)
  s.constrain(Distance(a, b, 5.0)) |> ignore
  s.constrain(Distance(a, c, 3.0)) |> ignore
  s.constrain(Distance(b, c, 4.0)) |> ignore
  let free = solved(s)
  assert_eq(free.report.local_dof, 3)
  s.constrain(Fix(a, 0.0, 0.0)) |> ignore
  s.constrain(Horizontal(s.add_line(a, b))) |> ignore
  let r = solved(s)
  assert_eq(r.report.local_dof, 0)
  near(sp(r, b).x, 5.0)
  near(sp(r, c).x, 1.8)
  near(sp(r, c).y, 2.4)
  near(distance(sp(r, a), sp(r, c)), 3.0)
  near(distance(sp(r, b), sp(r, c)), 4.0)
}

///|
test "directed angle selects both positive and negative branches" {
  for angle in [-2.8, -0.7, 0.7, 2.8] {
    let s = Sketch::new()
    let a = s.add_point(0.0, 0.0)
    let b = s.add_point(5.0, 0.0)
    let p = s.add_point(
      3.0 * @math.cos(angle + 0.2),
      3.0 * @math.sin(angle + 0.2),
    )
    let ab = s.add_line(a, b)
    let ap = s.add_line(a, p)
    s.constrain(Fix(a, 0.0, 0.0)) |> ignore
    s.constrain(Fix(b, 5.0, 0.0)) |> ignore
    s.constrain(Distance(a, p, 3.0)) |> ignore
    s.constrain(Angle(ab, ap, angle)) |> ignore
    let r = solved(s)
    near(sp(r, p).x, 3.0 * @math.cos(angle))
    near(sp(r, p).y, 3.0 * @math.sin(angle))
    assert_eq(r.report.local_dof, 0)
  }
}

///|
test "angle wraps continuously across the plus minus pi boundary" {
  let s = Sketch::new()
  let a = s.add_point(0.0, 0.0)
  let b = s.add_point(1.0, 0.0)
  let p = s.add_point(-1.0, -0.05)
  s.constrain(Fix(a, 0.0, 0.0)) |> ignore
  s.constrain(Fix(b, 1.0, 0.0)) |> ignore
  s.constrain(Distance(a, p, 1.0)) |> ignore
  s.constrain(Angle(s.add_line(a, b), s.add_line(a, p), @math.PI - 0.05))
  |> ignore
  let r = solved(s)
  near(sp(r, p).x, @math.cos(@math.PI - 0.05))
  near(sp(r, p).y, @math.sin(@math.PI - 0.05))
}

///|
test "parallel and equal length preserve a translated segment" {
  let s = Sketch::new()
  let a = s.add_point(0.0, 0.0)
  let b = s.add_point(3.0, 4.0)
  let c = s.add_point(10.0, 2.0)
  let d = s.add_point(12.0, 7.0)
  let ab = s.add_line(a, b)
  let cd = s.add_line(c, d)
  for (p, x, y) in [(a, 0.0, 0.0), (b, 3.0, 4.0), (c, 10.0, 2.0)] {
    s.constrain(Fix(p, x, y)) |> ignore
  }
  s.constrain(Parallel(ab, cd)) |> ignore
  s.constrain(EqualLength(ab, cd)) |> ignore
  let r = solved(s)
  near(sp(r, d).x, 13.0)
  near(sp(r, d).y, 6.0)
}

///|
test "perpendicular length constraint has analytic result" {
  let s = Sketch::new()
  let a = s.add_point(0.0, 0.0)
  let b = s.add_point(3.0, 4.0)
  let c = s.add_point(-3.0, 2.0)
  s.constrain(Fix(a, 0.0, 0.0)) |> ignore
  s.constrain(Fix(b, 3.0, 4.0)) |> ignore
  s.constrain(Perpendicular(s.add_line(a, b), s.add_line(a, c))) |> ignore
  s.constrain(Distance(a, c, 5.0)) |> ignore
  let r = solved(s)
  near(sp(r, c).x, -4.0)
  near(sp(r, c).y, 3.0)
}

///|
test "midpoint and coincidence solve independent points" {
  let s = Sketch::new()
  let a = s.add_point(1.0, 3.0)
  let b = s.add_point(7.0, 5.0)
  let p = s.add_point(2.0, 2.0)
  let q = s.add_point(5.0, 8.0)
  s.constrain(Fix(a, 1.0, 3.0)) |> ignore
  s.constrain(Fix(b, 7.0, 5.0)) |> ignore
  s.constrain(Midpoint(p, s.add_line(a, b))) |> ignore
  s.constrain(Coincident(p, q)) |> ignore
  let r = solved(s)
  near(sp(r, p).x, 4.0)
  near(sp(r, p).y, 4.0)
  near(sp(r, q).x, 4.0)
  near(sp(r, q).y, 4.0)
}

///|
test "point on infinite line can lie outside the segment" {
  let s = Sketch::new()
  let a = s.add_point(0.0, 0.0)
  let b = s.add_point(2.0, 1.0)
  let p = s.add_point(9.0, 3.0)
  s.constrain(Fix(a, 0.0, 0.0)) |> ignore
  s.constrain(Fix(b, 2.0, 1.0)) |> ignore
  s.constrain(DistanceX(a, p, 10.0)) |> ignore
  s.constrain(PointOnLine(p, s.add_line(a, b))) |> ignore
  let r = solved(s)
  near(sp(r, p).x, 10.0)
  near(sp(r, p).y, 5.0)
}

///|
test "circle radius, concentricity, equal radii, and point incidence" {
  let s = Sketch::new()
  let a = s.add_point(1.0, 2.0)
  let b = s.add_point(1.5, 2.5)
  let p = s.add_point(3.0, 6.0)
  let c = s.add_circle(a, 4.0)
  let d = s.add_circle(b, 3.0)
  s.constrain(Fix(a, 1.0, 2.0)) |> ignore
  s.constrain(Radius(c, 5.0)) |> ignore
  s.constrain(Concentric(c, d)) |> ignore
  s.constrain(EqualRadius(c, d)) |> ignore
  s.constrain(PointOnCircle(p, d)) |> ignore
  s.constrain(DistanceX(a, p, 3.0)) |> ignore
  let r = solved(s)
  near(r.radius(c).unwrap(), 5.0)
  near(r.radius(d).unwrap(), 5.0)
  near(sp(r, b).x, 1.0)
  near(sp(r, b).y, 2.0)
  near(sp(r, p).x, 4.0)
  near(sp(r, p).y, 6.0)
  assert_eq(r.report.local_dof, 0)
}

///|
test "line circle tangency works on either side and on a tilted line" {
  for side in [-1.0, 1.0] {
    let s = Sketch::new()
    let a = s.add_point(0.0, 0.0)
    let b = s.add_point(3.0, 4.0)
    // Unit left normal is (-0.8, 0.6).
    let center = s.add_point(-2.0 * side, 1.4 * side)
    let c = s.add_circle(center, 2.4)
    s.constrain(Fix(a, 0.0, 0.0)) |> ignore
    s.constrain(Fix(b, 3.0, 4.0)) |> ignore
    s.constrain(DistanceX(a, center, -2.4 * side)) |> ignore
    s.constrain(Radius(c, 3.0)) |> ignore
    s.constrain(Tangent(s.add_line(a, b), c)) |> ignore
    let r = solved(s)
    near(sp(r, center).x, -2.4 * side)
    near(sp(r, center).y, 1.8 * side)
    near((3.0 * sp(r, center).y - 4.0 * sp(r, center).x).abs() / 5.0, 3.0)
  }
}

///|
test "external tangent circles" {
  let s = Sketch::new()
  let a = s.add_point(0.0, 0.0)
  let b = s.add_point(4.0, 1.0)
  let c = s.add_circle(a, 2.5)
  let d = s.add_circle(b, 1.5)
  s.constrain(Fix(a, 0.0, 0.0)) |> ignore
  s.constrain(DistanceY(a, b, 0.0)) |> ignore
  s.constrain(Radius(c, 3.0)) |> ignore
  s.constrain(Radius(d, 2.0)) |> ignore
  s.constrain(ExternalTangent(c, d)) |> ignore
  let r = solved(s)
  near(sp(r, b).x, 5.0)
  near(sp(r, b).y, 0.0)
  near(
    distance(sp(r, a), sp(r, b)),
    r.radius(c).unwrap() + r.radius(d).unwrap(),
  )
}

///|
test "redundant equations are reported without declaring a conflict" {
  let s = Sketch::new()
  let a = s.add_point(0.3, 0.4)
  s.constrain(Fix(a, 0.0, 0.0)) |> ignore
  s.constrain(Fix(a, 0.0, 0.0)) |> ignore
  let r = solved(s)
  assert_eq(r.report.local_dof, 0)
  assert_eq(r.report.dependent_equations, 2)
  assert_eq(r.report.rank, 2)
}

///|
test "contradictory fixes return residuals and never mutate geometry" {
  let s = Sketch::new()
  let a = s.add_point(0.3, 0.4)
  s.constrain(Fix(a, 0.0, 0.0)) |> ignore
  s.constrain(Fix(a, 10.0, 0.0)) |> ignore
  let r = s.solve_and_apply().unwrap()
  assert_false(r.report.is_satisfied())
  assert_eq(r.report.unsatisfied().length(), 2)
  near(s.point(a).unwrap().x, 0.3)
  near(s.point(a).unwrap().y, 0.4)
  near(sp(r, a).x, 5.0)
}

///|
test "impossible triangle never reports satisfaction" {
  let s = Sketch::new()
  let a = s.add_point(0.0, 0.0)
  let b = s.add_point(6.0, 0.1)
  let c = s.add_point(2.0, 1.0)
  s.constrain(Fix(a, 0.0, 0.0)) |> ignore
  s.constrain(Distance(a, b, 7.0)) |> ignore
  s.constrain(Distance(a, c, 2.0)) |> ignore
  s.constrain(Distance(b, c, 3.0)) |> ignore
  let r = s.solve().unwrap()
  assert_false(r.report.is_satisfied())
  assert_true(r.report.unsatisfied().length() > 0)
}

///|
test "zero distance is represented by two coordinate equations" {
  let s = Sketch::new()
  let a = s.add_point(0.0, 0.0)
  let b = s.add_point(2.0, 3.0)
  s.constrain(Fix(a, 0.0, 0.0)) |> ignore
  s.constrain(Distance(a, b, 0.0)) |> ignore
  let r = solved(s)
  assert_eq(r.report.local_dof, 0)
  near(sp(r, b).x, 0.0)
  near(sp(r, b).y, 0.0)
}

///|
test "edit and apply preserve dimensions across repeated solves" {
  let s = Sketch::new()
  let a = s.add_point(0.0, 0.0)
  let b = s.add_point(4.0, 0.3)
  s.constrain(Fix(a, 0.0, 0.0)) |> ignore
  s.constrain(Horizontal(s.add_line(a, b))) |> ignore
  let dimension = s.constrain(Distance(a, b, 5.0))
  let r = s.solve_and_apply().unwrap()
  assert_true(r.report.is_satisfied())
  near(s.point(b).unwrap().x, 5.0)
  assert_true(s.set_constraint(dimension, Distance(a, b, 8.0)))
  assert_true(s.set_point(b, { x: 5.5, y: 0.2, }))
  let r = s.solve_and_apply().unwrap()
  assert_true(r.report.is_satisfied())
  near(s.point(b).unwrap().x, 8.0)
  near(s.point(b).unwrap().y, 0.0)
}

///|
test "iteration limit returns a nonconverged result" {
  let s = Sketch::new()
  let p = s.add_point(1.0, 1.0)
  s.constrain(Fix(p, 5.0, 3.0)) |> ignore
  let r = s
    .solve(options={ ..SolveOptions::default(), max_iterations: 1, })
    .unwrap()
  assert_false(r.report.is_satisfied())
  assert_eq(r.report.iterations, 1)
}

///|
test "bad input and invalid options are errors" {
  let s = Sketch::new()
  let p = s.add_point(0.0, 0.0)
  s.add_circle(p, -2.0) |> ignore
  assert_true(s.solve() is Err(_))
  let s = Sketch::new()
  s.add_point(0.0 / 0.0, 0.0) |> ignore
  assert_true(s.solve() is Err(_))
  let s = Sketch::new()
  let a = s.add_point(0.0, 0.0)
  s.add_line(a, a) |> ignore
  assert_true(s.solve() is Err(_))
  let s = Sketch::new()
  s.constrain(Horizontal(s.line_id(42))) |> ignore
  assert_true(s.solve() is Err(_))
  let s = Sketch::new()
  assert_true(
    s.solve(options={ ..SolveOptions::default(), length_tolerance: 0.0, })
    is Err(_),
  )
  assert_true(
    s.solve(options={ ..SolveOptions::default(), max_iterations: 0, }) is Err(_),
  )
}

///|
test "resource limits are explicit" {
  let s = Sketch::new()
  for i = 0; i < 129; i = i + 1 {
    s.add_point(i.to_double(), 0.0) |> ignore
  }
  assert_true(s.solve() is Err(_))
}

///|
test "maximum supported variable count solves a fully fixed sketch" {
  let s = Sketch::new()
  let points = []
  for i = 0; i < 128; i = i + 1 {
    let x = i.to_double()
    let p = s.add_point(x + 0.1, 0.2)
    points.push(p)
    s.constrain(Fix(p, x, 0.0)) |> ignore
  }
  let r = solved(s)
  assert_eq(r.report.variables, 256)
  assert_eq(r.report.local_dof, 0)
  near(sp(r, points[127]).x, 127.0)
}

///|
test "constraint and line count limits reject oversized models" {
  let s = Sketch::new()
  let a = s.add_point(0.0, 0.0)
  for i = 0; i < 512; i = i + 1 {
    s.constrain(Fix(a, 0.0, 0.0)) |> ignore
  }
  let r = solved(s)
  assert_eq(r.report.equations, 1024)
  assert_eq(r.report.rank, 2)
  s.constrain(Fix(a, 0.0, 0.0)) |> ignore
  assert_true(s.solve() is Err(_))
  let s = Sketch::new()
  let a = s.add_point(0.0, 0.0)
  let b = s.add_point(1.0, 0.0)
  for i = 0; i < 513; i = i + 1 {
    s.add_line(a, b) |> ignore
  }
  assert_true(s.solve() is Err(_))
}

///|
test "successful circle solve applies both center coordinates and radius" {
  let s = Sketch::new()
  let p = s.add_point(0.0, 0.0)
  let c = s.add_circle(p, 1.5)
  s.constrain(Fix(p, 2.0, 3.0)) |> ignore
  s.constrain(Radius(c, 4.0)) |> ignore
  let r = s.solve_and_apply().unwrap()
  assert_true(r.report.is_satisfied())
  near(s.point(p).unwrap().x, 2.0)
  near(s.point(p).unwrap().y, 3.0)
  near(s.radius(c).unwrap(), 4.0)
}

///|
test "signed offsets permit negative dimensions and antiparallel is parallel" {
  let s = Sketch::new()
  let a = s.add_point(0.0, 0.0)
  let b = s.add_point(-1.5, -2.5)
  s.constrain(Fix(a, 0.0, 0.0)) |> ignore
  s.constrain(DistanceX(a, b, -2.0)) |> ignore
  s.constrain(DistanceY(a, b, -3.0)) |> ignore
  s.constrain(Parallel(s.add_line(a, b), s.add_line(b, a))) |> ignore
  let r = solved(s)
  near(sp(r, b).x, -2.0)
  near(sp(r, b).y, -3.0)
  assert_eq(r.report.local_dof, 0)
  assert_eq(r.report.dependent_equations, 1)
}
