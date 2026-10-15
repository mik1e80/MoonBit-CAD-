///|
fn solve_error(s : Sketch) -> String raise {
  match s.solve() {
    Err(e) => e
    Ok(_) => fail("Expected invalid geometry to return an error")
  }
}

///|
test "diagnostics identify the offending geometry index" {
  let s = Sketch::new()
  s.add_point(0.0, 0.0) |> ignore
  s.add_point(1.0 / 0.0, 0.0) |> ignore
  assert_true(solve_error(s).contains("Point at index 1"))
  let s = Sketch::new()
  let a = s.add_point(0.0, 0.0)
  let b = s.add_point(1.0, 0.0)
  s.add_line(a, b) |> ignore
  s.add_line(a, a) |> ignore
  assert_true(solve_error(s).contains("Line at index 1"))
  let s = Sketch::new()
  let a = s.add_point(0.0, 0.0)
  s.add_circle(a, 1.0) |> ignore
  s.add_circle(a, -1.0) |> ignore
  assert_true(solve_error(s).contains("Circle at index 1"))
}

///|
test "residual identifiers locate the original conflicting relations" {
  let s = Sketch::new()
  let p = s.add_point(0.0, 0.0)
  let first = s.constrain(Fix(p, 0.0, 0.0))
  let second = s.constrain(Fix(p, 10.0, 0.0))
  let r = s.solve().unwrap()
  assert_false(r.report.is_satisfied())
  for finding in r.report.unsatisfied() {
    assert_true(s.constraint(finding.id) is Some(Fix(_, _, _)))
    assert_true(r.report.residual(finding.id).unwrap().tolerance_ratio > 1.0)
  }
  assert_true(r.report.residual(first).unwrap().length_error > 4.9)
  assert_true(r.report.residual(second).unwrap().length_error > 4.9)
  assert_true(s.constraint({ index: 5, }) is None)
  assert_true(r.report.residual({ index: 5, }) is None)
}

///|
test "editing a radius preserves its incident point constraints" {
  let s = Sketch::new()
  let center = s.add_point(0.0, 0.0)
  let p = s.add_point(3.0, 4.0)
  let circle = s.add_circle(center, 1.0)
  s.constrain(Fix(center, 0.0, 0.0)) |> ignore
  s.constrain(Fix(p, 3.0, 4.0)) |> ignore
  s.constrain(PointOnCircle(p, circle)) |> ignore
  for initial in [2.0, 8.0] {
    assert_true(s.set_radius(circle, initial))
    near(s.radius(circle).unwrap(), initial)
    let r = s.solve_and_apply().unwrap()
    assert_true(r.report.is_satisfied())
    assert_eq(r.report.local_dof, 0)
    near(s.radius(circle).unwrap(), 5.0)
    near(s.point(p).unwrap().x, 3.0)
    near(s.point(p).unwrap().y, 4.0)
  }
  assert_false(s.set_radius({ index: 9, }, 1.0))
}

///|
test "invalid edited radius is diagnosed and can be repaired" {
  let s = Sketch::new()
  let p = s.add_point(1.0, 2.0)
  let c = s.add_circle(p, 3.0)
  assert_true(s.set_radius(c, 0.0))
  assert_true(s.solve_and_apply() is Err(_))
  near(s.point(p).unwrap().x, 1.0)
  near(s.point(p).unwrap().y, 2.0)
  assert_true(s.set_radius(c, 4.0))
  assert_true(s.solve_and_apply().unwrap().report.is_satisfied())
}
