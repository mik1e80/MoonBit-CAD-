///|
test "nonfinite evaluation and output overflow have numerical error types" {
  let s = Sketch::new()
  s.add_point(0.0, 0.0) |> ignore
  assert_true(
    s.evaluate([1.0 / 0.0, 0.0], s.frame()) is Err(NumericalFailure(_)),
  )
  assert_true(
    s.solution(
      [1.0 / 0.0, 0.0],
      s.frame(),
      SolveOptions::default(),
      Satisfied,
      0,
    )
    is Err(NumericalFailure(_)),
  )
}

///|
test "evaluation preserves geometry domain error identifiers" {
  let s = Sketch::new()
  let a = s.add_point(0.0, 0.0)
  let b = s.add_point(1.0, 0.0)
  let line = s.add_line(a, b)
  let circle = s.add_circle(a, 1.0)
  assert_true(
    s.evaluate([0.0, 0.0, 0.0, 0.0, 1.0], s.frame()) is Err(DegenerateLine(id)) &&
    id.index == line.index,
  )
  assert_true(
    s.evaluate([0.0, 0.0, 1.0, 0.0, 0.0], s.frame()) is Err(InvalidRadius(id)) &&
    id.index == circle.index,
  )
}

///|
test "same sketch missing references are distinguished from foreign handles" {
  let s = Sketch::new()
  let p = s.add_point(0.0, 0.0)
  let bad = s.constrain(Distance(p, s.point_id(99), 1.0))
  assert_true(s.solve() is Err(InvalidConstraint(id)) && id.index == bad.index)
  let s = Sketch::new()
  s.add_circle(s.point_id(99), 1.0) |> ignore
  assert_true(s.solve() is Err(InvalidGeometry(_)))
}
