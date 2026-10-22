///|
test "typed errors identify invalid geometry and preserve stored points" {
  let s = @sketch.Sketch::new()
  let p = s.add_point(1.0 / 0.0, 2.0)
  assert_true(s.solve() is Err(InvalidGeometry(_)))
  assert_true(s.solve_and_apply() is Err(InvalidGeometry(_)))
  assert_eq(s.point(p).unwrap().y, 2.0)
}

///|
test "typed errors identify degenerate lines and invalid radii" {
  let s = @sketch.Sketch::new()
  let a = s.add_point(2.0, 3.0)
  let line = s.add_line(a, a)
  assert_true(s.solve() is Err(DegenerateLine(id)) && id.index == line.index)
  let s = @sketch.Sketch::new()
  let a = s.add_point(2.0, 3.0)
  let circle = s.add_circle(a, -2.0)
  assert_true(
    s.solve_and_apply() is Err(InvalidRadius(id)) && id.index == circle.index,
  )
  assert_eq(s.radius(circle).unwrap(), -2.0)
}

///|
test "typed errors reject foreign handles in geometry and constraints" {
  let other = @sketch.Sketch::new()
  let foreign = other.add_point(0.0, 0.0)
  let s = @sketch.Sketch::new()
  let a = s.add_point(2.0, 3.0)
  s.add_line(a, foreign) |> ignore
  assert_true(s.solve() is Err(ForeignHandle))
  let s = @sketch.Sketch::new()
  s.add_circle(foreign, 1.0) |> ignore
  assert_true(s.solve() is Err(ForeignHandle))
  let s = @sketch.Sketch::new()
  let own = s.add_point(2.0, 3.0)
  let constraint = s.constrain(Distance(own, foreign, 5.0))
  assert_true(s.solve_and_apply() is Err(ForeignHandle))
  assert_true(s.set_constraint_enabled(constraint, false))
  assert_true(s.solve().unwrap().report.is_satisfied())
  assert_true(s.set_constraint_enabled(constraint, true))
  assert_true(s.solve() is Err(ForeignHandle))
}

///|
test "typed constraint errors use stable creation IDs after deletion" {
  let s = @sketch.Sketch::new()
  let a = s.add_point(0.0, 0.0)
  let b = s.add_point(2.0, 0.0)
  let removed = s.constrain(Fix(a, 0.0, 0.0))
  let bad = s.constrain(Distance(a, b, -1.0))
  assert_true(s.remove_constraint(removed))
  assert_true(
    s.solve() is Err(InvalidConstraint(id)) && id.index() == bad.index(),
  )
}

///|
test "typed resource limit leaves geometry unchanged" {
  let s = @sketch.Sketch::new()
  let p = s.add_point(4.0, 5.0)
  for i = 0; i < 128; i = i + 1 {
    s.add_point(i.to_double(), 0.0) |> ignore
  }
  assert_true(s.solve() is Err(ResourceLimit))
  assert_true(s.solve_and_apply() is Err(ResourceLimit))
  assert_eq(s.point(p).unwrap().x, 4.0)
  assert_eq(s.point(p).unwrap().y, 5.0)
}

///|
test "typed options errors are separate from invalid geometry" {
  let s = @sketch.Sketch::new()
  for
    options in [
      { ..@sketch.SolveOptions::default(), max_iterations: 0, },
      { ..@sketch.SolveOptions::default(), length_tolerance: -1.0, },
      { ..@sketch.SolveOptions::default(), rank_tolerance: 0.0, },
    ] {
    assert_true(s.solve(options~) is Err(InvalidOptions(_)))
  }
  s.add_point(0.0, 0.0) |> ignore
  s.add_point(1.0e50, 0.0) |> ignore
  assert_true(s.solve() is Err(InvalidOptions(_)))
}

///|
test "nonconvergence remains a report and does not apply geometry" {
  let s = @sketch.Sketch::new()
  let p = s.add_point(2.0, 3.0)
  s.constrain(Fix(p, 0.0, 0.0)) |> ignore
  s.constrain(Fix(p, 10.0, 0.0)) |> ignore
  let solution = s.solve_and_apply().unwrap()
  assert_false(solution.report.is_satisfied())
  assert_eq(s.point(p).unwrap().x, 2.0)
  assert_eq(s.point(p).unwrap().y, 3.0)
}

///|
test "typed errors expose readable messages without string parsing" {
  let error : @sketch.SketchError = ForeignHandle
  let action = match error {
    ForeignHandle => "use handles from the same sketch"
    ResourceLimit => "split the sketch"
    _ => error.message()
  }
  assert_eq(action, "use handles from the same sketch")
  assert_true(error.message().length() > 0)
}
