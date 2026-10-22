///|
test "four-bar drive changes local DOF and keeps its original handle" {
  let mechanism = new_four_bar({
    ground: 80.0,
    crank: 30.0,
    coupler: 70.0,
    rocker: 50.0,
  })
  mechanism.advance(0) |> ignore
  let drive_id = mechanism.drive.index()
  assert_eq(mechanism.free_dof(), 1)
  for step = 1; step <= 6; step = step + 1 {
    let pose = mechanism.advance(step * 15)
    assert_eq(pose.report.local_dof, 0)
    assert_eq(mechanism.drive.index(), drive_id)
    assert_true(pose.report.residual(mechanism.drive).unwrap().active)
  }
}

///|
test "different link lengths preserve the lower assembly on forward and reverse sweeps" {
  let mechanism = new_four_bar(
    { ground: 60.0, crank: 20.0, coupler: 50.0, rocker: 40.0, },
    upper=false,
  )
  for step = 0; step <= 12; step = step + 1 {
    mechanism.advance(step * 15) |> ignore
  }
  for step = 11; step >= 0; step = step - 1 {
    mechanism.advance(step * 15) |> ignore
  }
  let b = mechanism.sketch.point(mechanism.points[1]).unwrap()
  let c = mechanism.sketch.point(mechanism.points[2]).unwrap()
  assert_true(c.y < b.y)
}
