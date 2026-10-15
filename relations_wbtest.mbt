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
