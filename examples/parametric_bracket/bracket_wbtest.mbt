///|
test "bracket changes height and both margins without replacing geometry handles" {
  let first : Parameters = {
    width: 105.0,
    height: 65.0,
    hole_radius: 4.0,
    horizontal_margin: 17.0,
    vertical_margin: 12.0,
  }
  let bracket = new_bracket(first)
  bracket.solve_checked(first) |> ignore
  let second : Parameters = {
    width: 150.0,
    height: 90.0,
    hole_radius: 6.0,
    horizontal_margin: 26.0,
    vertical_margin: 19.0,
  }
  let id = bracket.horizontal_margin.index()
  bracket.edit(second)
  let result = bracket.solve_checked(second)
  assert_eq(bracket.horizontal_margin.index(), id)
  assert_true(result.report.residual(bracket.horizontal_margin).unwrap().active)
  bracket.reject_conflict(second) |> ignore
  assert_true(bracket.sketch.set_constraint_enabled(bracket.conflict, false))
  bracket.solve_checked(second) |> ignore
}
