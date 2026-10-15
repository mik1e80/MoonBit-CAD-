///|
test "foreign point handles cannot read or modify another sketch" {
  let a = Sketch::new()
  let b = Sketch::new()
  let ap = a.add_point(1.0, 2.0)
  let bp = b.add_point(9.0, 8.0)
  assert_true(b.point(ap) is None)
  assert_false(b.set_point(ap, { x: 0.0, y: 0.0, }))
  near(b.point(bp).unwrap().x, 9.0)
  near(b.point(bp).unwrap().y, 8.0)
}

///|
test "foreign geometry in a relation is rejected instead of silently remapped" {
  let a = Sketch::new()
  let ap = a.add_point(0.0, 0.0)
  let aq = a.add_point(1.0, 0.0)
  let al = a.add_line(ap, aq)
  let ac = a.add_circle(ap, 1.0)
  let b = Sketch::new()
  let bp = b.add_point(0.0, 0.0)
  let bq = b.add_point(1.0, 0.0)
  b.add_line(bp, bq) |> ignore
  b.add_circle(bp, 1.0) |> ignore
  let id = b.constrain(Fix(ap, 0.0, 0.0))
  assert_true(b.solve() is Err(_))
  b.set_constraint(id, Horizontal(al)) |> ignore
  assert_true(b.solve() is Err(_))
  b.set_constraint(id, Radius(ac, 2.0)) |> ignore
  assert_true(b.solve() is Err(_))
}

///|
test "foreign circle and constraint handles cannot edit another sketch" {
  let a = Sketch::new()
  let ap = a.add_point(0.0, 0.0)
  let ac = a.add_circle(ap, 1.0)
  let ai = a.constrain(Fix(ap, 0.0, 0.0))
  let b = Sketch::new()
  let bp = b.add_point(2.0, 3.0)
  let bc = b.add_circle(bp, 2.0)
  let bi = b.constrain(Fix(bp, 2.0, 3.0))
  assert_true(b.radius(ac) is None)
  assert_false(b.set_radius(ac, 9.0))
  assert_true(b.constraint(ai) is None)
  assert_true(b.constraint_enabled(ai) is None)
  assert_false(b.set_constraint(ai, Fix(bp, 99.0, 99.0)))
  assert_false(b.set_constraint_enabled(ai, false))
  assert_true(b.constraint_enabled(bi) is Some(true))
  near(b.radius(bc).unwrap(), 2.0)
}

///|
test "solutions and reports retain the originating sketch identity" {
  let a = Sketch::new()
  let ap = a.add_point(0.0, 0.0)
  let ac = a.add_circle(ap, 2.0)
  let ai = a.constrain(Radius(ac, 3.0))
  let b = Sketch::new()
  let bp = b.add_point(0.0, 0.0)
  let bc = b.add_circle(bp, 2.0)
  let bi = b.constrain(Radius(bc, 3.0))
  let r = solved(a)
  assert_true(r.point(bp) is None)
  assert_true(r.radius(bc) is None)
  assert_true(r.report.residual(bi) is None)
  assert_true(r.point(ap) is Some(_))
  near(r.radius(ac).unwrap(), 3.0)
  assert_true(r.report.residual(ai) is Some(_))
}

///|
test "foreign endpoints and circle centers invalidate geometry" {
  let a = Sketch::new()
  let ap = a.add_point(0.0, 0.0)
  let b = Sketch::new()
  let bp = b.add_point(1.0, 0.0)
  b.add_line(ap, bp) |> ignore
  assert_true(b.solve() is Err(_))
  let c = Sketch::new()
  c.add_point(0.0, 0.0) |> ignore
  c.add_circle(ap, 1.0) |> ignore
  assert_true(c.solve() is Err(_))
}
