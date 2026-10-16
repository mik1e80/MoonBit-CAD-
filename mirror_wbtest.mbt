///|
test "mirror solves analytic reflections across translated rotated axes" {
  for i = 0; i < 24; i = i + 1 {
    let scale = [1.0e-4, 1.0, 1.0e4][i % 3]
    let phase = i.to_double() * 0.31
    let ux = @math.cos(phase)
    let uy = @math.sin(phase)
    let ox = 300.0 * scale
    let oy = -200.0 * scale
    let along = 3.0 * scale
    let normal = (if i % 2 == 0 { 2.0 } else { -2.0 }) * scale
    let px = ox + along * ux - normal * uy
    let py = oy + along * uy + normal * ux
    let qx = ox + along * ux + normal * uy
    let qy = oy + along * uy - normal * ux
    let s = Sketch::new()
    let a = s.add_point(ox, oy)
    let b = s.add_point(ox + 5.0 * scale * ux, oy + 5.0 * scale * uy)
    let p = s.add_point(px, py)
    let q = s.add_point(qx + 0.1 * scale, qy - 0.2 * scale)
    let axis = if i % 2 == 0 { s.add_line(a, b) } else { s.add_line(b, a) }
    s.constrain(Fix(a, ox, oy)) |> ignore
    s.constrain(Fix(b, ox + 5.0 * scale * ux, oy + 5.0 * scale * uy)) |> ignore
    s.constrain(Fix(p, px, py)) |> ignore
    let relation = s.constrain(Mirror(p, q, axis))
    let tolerance = 1.0e-8 * scale
    let r = solved(s, options={
      ..SolveOptions::default(),
      length_tolerance: tolerance,
    })
    assert_eq(r.report.local_dof, 0)
    assert_eq(r.report.equations, 8)
    near(sp(r, q).x, qx, tol=3.0 * tolerance)
    near(sp(r, q).y, qy, tol=3.0 * tolerance)
    assert_true(r.report.residual(relation).unwrap().tolerance_ratio <= 1.0)
  }
}

///|
test "a point mirrored onto itself lies on the axis" {
  let s = Sketch::new()
  let a = s.add_point(0.0, 2.0)
  let b = s.add_point(5.0, 2.0)
  let p = s.add_point(3.0, 4.0)
  let axis = s.add_line(a, b)
  s.constrain(Fix(a, 0.0, 2.0)) |> ignore
  s.constrain(Fix(b, 5.0, 2.0)) |> ignore
  s.constrain(DistanceX(a, p, 3.0)) |> ignore
  s.constrain(Mirror(p, p, axis)) |> ignore
  let r = solved(s)
  near(sp(r, p).y, 2.0)
  near(sp(r, p).x, 3.0)
  assert_eq(r.report.local_dof, 0)
}

///|
test "self mirror retains one free tangential direction" {
  let s = Sketch::new()
  let a = s.add_point(0.0, 0.0)
  let b = s.add_point(3.0, 4.0)
  let p = s.add_point(1.5, 2.0)
  s.constrain(Fix(a, 0.0, 0.0)) |> ignore
  s.constrain(Fix(b, 3.0, 4.0)) |> ignore
  s.constrain(Mirror(p, p, s.add_line(a, b))) |> ignore
  assert_eq(solved(s).report.local_dof, 1)
}

///|
test "mirror accepts coincident distinct points on the axis" {
  let s = Sketch::new()
  let a = s.add_point(0.0, 0.0)
  let b = s.add_point(3.0, 4.0)
  let p = s.add_point(1.5, 2.0)
  let q = s.add_point(1.5, 2.0)
  s.constrain(Fix(a, 0.0, 0.0)) |> ignore
  s.constrain(Fix(b, 3.0, 4.0)) |> ignore
  s.constrain(Fix(p, 1.5, 2.0)) |> ignore
  s.constrain(Mirror(p, q, s.add_line(a, b))) |> ignore
  let r = solved(s)
  assert_eq(r.report.local_dof, 0)
  near(sp(r, q).x, 1.5)
  near(sp(r, q).y, 2.0)
}

///|
test "mirror rejects foreign points axes and a degenerate axis" {
  let foreign = Sketch::new()
  let fp = foreign.add_point(0.0, 0.0)
  let fq = foreign.add_point(1.0, 0.0)
  let fl = foreign.add_line(fp, fq)
  let s = Sketch::new()
  let a = s.add_point(0.0, 0.0)
  let b = s.add_point(1.0, 0.0)
  let axis = s.add_line(a, b)
  let relation = s.constrain(Mirror(fp, b, axis))
  assert_true(s.solve() is Err(_))
  s.set_constraint(relation, Mirror(a, b, fl)) |> ignore
  assert_true(s.solve() is Err(_))
  s.set_constraint(relation, Mirror(a, b, axis)) |> ignore
  s.set_point(b, { x: 0.0, y: 0.0, }) |> ignore
  assert_true(s.solve() is Err(_))
}

///|
test "mirror conflict retains geometry and supports relation suppression" {
  let s = Sketch::new()
  let a = s.add_point(0.0, 0.0)
  let b = s.add_point(5.0, 0.0)
  let p = s.add_point(2.0, 3.0)
  let q = s.add_point(2.0, 4.0)
  s.constrain(Fix(a, 0.0, 0.0)) |> ignore
  s.constrain(Fix(b, 5.0, 0.0)) |> ignore
  s.constrain(Fix(p, 2.0, 3.0)) |> ignore
  let fixed = s.constrain(Fix(q, 2.0, 4.0))
  s.constrain(Mirror(p, q, s.add_line(a, b))) |> ignore
  assert_false(s.solve_and_apply().unwrap().report.is_satisfied())
  near(s.point(q).unwrap().y, 4.0)
  s.set_constraint_enabled(fixed, false) |> ignore
  let r = s.solve_and_apply().unwrap()
  assert_true(r.report.is_satisfied())
  near(s.point(q).unwrap().x, 2.0)
  near(s.point(q).unwrap().y, -3.0)
}
