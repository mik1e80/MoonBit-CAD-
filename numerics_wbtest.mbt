///|
test "automatic derivatives match independent centered differences for every constraint" {
  let s = Sketch::new()
  let a = s.add_point(0.1, 0.2)
  let b = s.add_point(3.2, 1.1)
  let c = s.add_point(1.3, 4.2)
  let d = s.add_point(4.1, 3.3)
  let ab = s.add_line(a, b)
  let cd = s.add_line(c, d)
  let ca = s.add_circle(a, 2.1)
  let cc = s.add_circle(c, 1.2)
  for
    constraint in [
      Fix(a, 0.0, 0.0),
      Coincident(a, c),
      Symmetric(b, d, a),
      Mirror(b, d, ab),
      Horizontal(ab),
      Vertical(cd),
      Distance(a, c, 3.0),
      DistanceX(a, d, 4.0),
      DistanceY(b, c, 3.0),
      Parallel(ab, cd),
      Perpendicular(ab, cd),
      Angle(ab, cd, 0.7),
      EqualLength(ab, cd),
      LengthRatio(ab, cd, 2.5),
      Midpoint(d, ab),
      PointOnLine(c, ab),
      DistanceToLine(c, ab, -1.5),
      Radius(ca, 2.0),
      EqualRadius(ca, cc),
      Concentric(ca, cc),
      PointOnCircle(d, ca),
      Tangent(ab, cc),
      ExternalTangent(ca, cc),
      InternalTangent(ca, cc),
    ] {
    s.constrain(constraint) |> ignore
  }
  let frame = s.frame()
  let x = s.parameters(frame)
  let rows = s.evaluate(x, frame).unwrap()
  let h = 1.0e-6
  for k = 0; k < x.length(); k = k + 1 {
    let xp = x.copy()
    let xm = x.copy()
    xp[k] = xp[k] + h
    xm[k] = xm[k] - h
    let rp = s.evaluate(xp, frame).unwrap()
    let rm = s.evaluate(xm, frame).unwrap()
    for i = 0; i < rows.length(); i = i + 1 {
      let numeric = (rp[i].jet.v - rm[i].jet.v) / (2.0 * h)
      near(rows[i].jet.d[k], numeric, tol=1.0e-7)
    }
  }
}

///|
test "QR recovers a nearly dependent linear system" {
  let j = [[1.0, 1.0], [1.0, 1.000001], [1.0, 0.999999]]
  let expected = [2.0, -3.0]
  let r = j.map(row => -(row[0] * expected[0] + row[1] * expected[1]))
  let x = damped_step(j, r, 2, 1.0e-18).unwrap()
  near(x[0], expected[0], tol=1.0e-4)
  near(x[1], expected[1], tol=1.0e-4)
}

///|
test "rank is invariant under row scaling and catches repeated equations" {
  assert_eq(numerical_rank([[1.0e-20, 0.0], [0.0, 1.0e20]], 2, 1.0e-9), 2)
  assert_eq(
    numerical_rank([[1.0, 2.0], [-3.0, -6.0], [0.0, 0.0]], 2, 1.0e-9),
    1,
  )
  assert_eq(numerical_rank([], 3, 1.0e-9), 0)
}

///|
test "large origin rounding cannot give a false success" {
  let s = Sketch::new()
  let a = s.add_point(1.0e12, 1.0e12)
  let b = s.add_point(1.0e12 + 1.0, 1.0e12)
  s.constrain(Fix(a, 1.0e12, 1.0e12)) |> ignore
  s.constrain(DistanceX(a, b, 1.0 / 3.0)) |> ignore
  s.constrain(DistanceY(a, b, 0.0)) |> ignore
  let r = s.solve_and_apply().unwrap()
  assert_false(r.report.is_satisfied())
  assert_true(r.report.unsatisfied().length() > 0)
  near(s.point(b).unwrap().x, 1.0e12 + 1.0)
  let actual = (sp(r, b).x - sp(r, a).x - 1.0 / 3.0).abs()
  near(r.report.residuals[1].length_error, actual, tol=1.0e-12)
}

///|
test "coincident initial guess may stall without proving inconsistency" {
  let s = Sketch::new()
  let a = s.add_point(0.0, 0.0)
  let b = s.add_point(0.0, 0.0)
  s.constrain(Distance(a, b, 1.0)) |> ignore
  let stalled = s.solve().unwrap()
  assert_false(stalled.report.is_satisfied())
  assert_true(s.set_point(b, { x: 0.2, y: 0.1, }))
  let r = solved(s)
  near(distance(sp(r, a), sp(r, b)), 1.0)
}

///|
test "four bar linkage follows changing crank positions" {
  let s = Sketch::new()
  let a = s.add_point(0.0, 0.0)
  let b = s.add_point(4.0, 0.0)
  let c = s.add_point(1.9, 0.6)
  let d = s.add_point(5.0, 2.8)
  s.constrain(Fix(a, 0.0, 0.0)) |> ignore
  s.constrain(Fix(b, 4.0, 0.0)) |> ignore
  let crank = s.constrain(Fix(c, 2.0 * @math.cos(0.3), 2.0 * @math.sin(0.3)))
  s.constrain(Distance(c, d, 4.0)) |> ignore
  s.constrain(Distance(b, d, 3.0)) |> ignore
  for i = 0; i < 21; i = i + 1 {
    let angle = 0.3 + i.to_double() * 0.05
    let cx = 2.0 * @math.cos(angle)
    let cy = 2.0 * @math.sin(angle)
    assert_true(s.set_constraint(crank, Fix(c, cx, cy)))
    let r = s.solve_and_apply().unwrap()
    assert_true(r.report.is_satisfied())
    assert_eq(r.report.local_dof, 0)
    let p = sp(r, d)
    // Independent circle-circle intersection formula, upper assembly branch.
    let dx = cx - 4.0
    let dy = cy
    let base = @math.hypot(dx, dy)
    let along = (9.0 - 16.0 + base * base) / (2.0 * base)
    let height = (9.0 - along * along).sqrt()
    let expected_x = 4.0 + along * dx / base + height * dy / base
    let expected_y = along * dy / base - height * dx / base
    near(p.x, expected_x)
    near(p.y, expected_y)
    near(distance(p, sp(r, c)), 4.0)
    near(distance(p, sp(r, b)), 3.0)
  }
}

///|
test "singular collinear triangle only has a first order DOF estimate" {
  let s = Sketch::new()
  let a = s.add_point(0.0, 0.0)
  let b = s.add_point(1.0, 0.0)
  let c = s.add_point(2.0, 0.0)
  s.constrain(Distance(a, b, 1.0)) |> ignore
  s.constrain(Distance(b, c, 1.0)) |> ignore
  s.constrain(Distance(a, c, 2.0)) |> ignore
  let r = solved(s)
  assert_eq(r.report.rank, 2)
  assert_eq(r.report.local_dof, 4)
  assert_eq(r.report.dependent_equations, 1)
}

///|
test "invalid dimensions, references, and numerical limits are rejected" {
  for dimension in [-1.0, 0.0 / 0.0, 1.0 / 0.0] {
    let s = Sketch::new()
    let a = s.add_point(0.0, 0.0)
    let b = s.add_point(1.0, 0.0)
    s.constrain(Distance(a, b, dimension)) |> ignore
    assert_true(s.solve() is Err(_))
  }
  let s = Sketch::new()
  s.add_circle(s.point_id(20), 1.0) |> ignore
  assert_true(s.solve() is Err(_))
  let s = Sketch::new()
  let a = s.add_point(0.0, 0.0)
  let b = s.add_point(1.0, 0.0)
  let l = s.add_line(a, b)
  s.constrain(Angle(l, l, 10.0)) |> ignore
  assert_true(s.solve() is Err(_))
  let s = Sketch::new()
  s.add_point(1.0e101, 0.0) |> ignore
  assert_true(s.solve() is Err(_))
  let s = Sketch::new()
  let a = s.add_point(0.0, 0.0)
  let b = s.add_point(1.0e-15, 0.0)
  let c = s.add_point(1.0, 1.0)
  s.add_line(a, b) |> ignore
  s.add_line(a, c) |> ignore
  assert_true(s.solve() is Err(_))
  let s = Sketch::new()
  for tol in [0.0, -1.0, 0.0 / 0.0, 1.0 / 0.0, 1.0e-20] {
    assert_true(
      s.solve(options={ ..SolveOptions::default(), length_tolerance: tol, })
      is Err(_),
    )
  }
}
