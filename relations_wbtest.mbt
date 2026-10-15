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
  s.set_constraint(c, DistanceToLine({ index: 9, }, l, 1.0)) |> ignore
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
  s.set_constraint(id, Symmetric(a, b, { index: 99, })) |> ignore
  assert_true(s.solve() is Err(_))
}
