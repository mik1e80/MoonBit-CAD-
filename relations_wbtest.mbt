///|
test "signed line offset handles both sides and reversed line direction" {
  for side in [-1.0, 0.0, 1.0] {
    for reverse in [false, true] {
      let s = Sketch::new()
      let a = s.add_point(0.0, 0.0)
      let b = s.add_point(3.0, 4.0)
      let p = s.add_point(-2.0 * side, 1.4 * side + 0.1)
      let l = if reverse { s.add_line(b, a) } else { s.add_line(a, b) }
      s.constrain(Fix(a, 0.0, 0.0)) |> ignore
      s.constrain(Fix(b, 3.0, 4.0)) |> ignore
      s.constrain(DistanceX(a, p, -2.4 * side)) |> ignore
      let sign = if reverse { -1.0 } else { 1.0 }
      s.constrain(DistanceToLine(p, l, 3.0 * side * sign)) |> ignore
      let r = solved(s)
      near(sp(r, p).x, -2.4 * side)
      near(sp(r, p).y, 1.8 * side)
      near((3.0 * sp(r, p).y - 4.0 * sp(r, p).x) / 5.0, 3.0 * side)
      assert_eq(r.report.local_dof, 0)
    }
  }
}

///|
test "line offset validates dimensions and references" {
  let s = Sketch::new()
  let a = s.add_point(0.0, 0.0)
  let b = s.add_point(1.0, 0.0)
  let l = s.add_line(a, b)
  let c = s.constrain(DistanceToLine(a, l, 1.0 / 0.0))
  assert_true(s.solve() is Err(_))
  s.set_constraint(c, DistanceToLine(s.point_id(9), l, 1.0)) |> ignore
  assert_true(s.solve() is Err(_))
}

///|
test "point symmetry solves the reflected endpoint across scales" {
  for scale in [1.0e-6, 1.0, 1.0e6] {
    let s = Sketch::new()
    let a = s.add_point(-3.0 * scale, 4.0 * scale)
    let b = s.add_point(5.0 * scale, -6.0 * scale)
    let center = s.add_point(2.0 * scale, -1.0 * scale)
    s.constrain(Fix(a, -3.0 * scale, 4.0 * scale)) |> ignore
    s.constrain(Fix(center, 2.0 * scale, -1.0 * scale)) |> ignore
    s.constrain(Symmetric(a, b, center)) |> ignore
    let r = solved(s, options={
      ..SolveOptions::default(),
      length_tolerance: 1.0e-8 * scale,
    })
    assert_eq(r.report.local_dof, 0)
    near(sp(r, b).x, 7.0 * scale, tol=5.0e-8 * scale)
    near(sp(r, b).y, -6.0 * scale, tol=5.0e-8 * scale)
  }
}

///|
test "point symmetry can solve the center and rejects an absent center" {
  let s = Sketch::new()
  let a = s.add_point(-2.0, 3.0)
  let b = s.add_point(8.0, 7.0)
  let c = s.add_point(1.0, 2.0)
  s.constrain(Fix(a, -2.0, 3.0)) |> ignore
  s.constrain(Fix(b, 8.0, 7.0)) |> ignore
  let id = s.constrain(Symmetric(a, b, c))
  let r = solved(s)
  near(sp(r, c).x, 3.0)
  near(sp(r, c).y, 5.0)
  s.set_constraint(id, Symmetric(a, b, s.point_id(99))) |> ignore
  assert_true(s.solve() is Err(_))
}

///|
test "length ratios constrain either longer or shorter geometry" {
  for ratio in [0.5, 1.0, 2.0] {
    let s = Sketch::new()
    let a = s.add_point(0.0, 0.0)
    let b = s.add_point(3.0, 4.0)
    let c = s.add_point(10.0, 0.0)
    let d = s.add_point(10.0 + 4.0 * ratio, 0.1)
    let ab = s.add_line(a, b)
    let cd = s.add_line(c, d)
    s.constrain(Fix(a, 0.0, 0.0)) |> ignore
    s.constrain(Fix(b, 3.0, 4.0)) |> ignore
    s.constrain(Fix(c, 10.0, 0.0)) |> ignore
    s.constrain(Horizontal(cd)) |> ignore
    s.constrain(LengthRatio(cd, ab, ratio)) |> ignore
    let r = solved(s)
    near(sp(r, d).x, 10.0 + 5.0 * ratio)
    near(sp(r, d).y, 0.0)
    near(distance(sp(r, c), sp(r, d)), ratio * distance(sp(r, a), sp(r, b)))
    assert_eq(r.report.local_dof, 0)
  }
}

///|
test "invalid length ratios are rejected" {
  for ratio in [0.0, -1.0, 1.0e13, 0.0 / 0.0, 1.0 / 0.0] {
    let s = Sketch::new()
    let a = s.add_point(0.0, 0.0)
    let b = s.add_point(1.0, 0.0)
    let l = s.add_line(a, b)
    s.constrain(LengthRatio(l, l, ratio)) |> ignore
    assert_true(s.solve() is Err(_))
  }
}

///|
test "internal tangent circles match analytic center positions" {
  for side in [-1.0, 1.0] {
    let s = Sketch::new()
    let a = s.add_point(0.0, 0.0)
    let b = s.add_point(3.2, 3.8 * side)
    let outer = s.add_circle(a, 5.0)
    let inner = s.add_circle(b, 1.5)
    s.constrain(Fix(a, 0.0, 0.0)) |> ignore
    s.constrain(DistanceX(a, b, 3.0)) |> ignore
    s.constrain(Radius(outer, 7.0)) |> ignore
    s.constrain(Radius(inner, 2.0)) |> ignore
    s.constrain(InternalTangent(outer, inner)) |> ignore
    let r = solved(s)
    near(sp(r, b).x, 3.0)
    near(sp(r, b).y, 4.0 * side)
    near(distance(sp(r, a), sp(r, b)), 5.0)
    near(
      distance(sp(r, a), sp(r, b)) + r.radius(inner).unwrap(),
      r.radius(outer).unwrap(),
    )
    assert_eq(r.report.local_dof, 0)
  }
}

///|
test "internal tangency rejects equal circles and reversed nesting" {
  for radii in [(2.0, 2.0), (1.0, 2.0)] {
    let s = Sketch::new()
    let a = s.add_point(0.0, 0.0)
    let b = s.add_point(1.0, 0.0)
    let outer = s.add_circle(a, radii.0)
    let inner = s.add_circle(b, radii.1)
    let bad = s.constrain(InternalTangent(outer, inner))
    assert_true(
      solve_error(s) is InvalidConstraint(id) && id.index == bad.index,
    )
  }
}
