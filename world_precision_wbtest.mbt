///|
test "satisfaction agrees with direct world coordinate measurement near tolerance" {
  for i = 0; i < 96; i = i + 1 {
    let s = Sketch::new()
    s.add_point(-1.0e8, 0.0) |> ignore
    let p = s.add_point(1.0e8, 0.0)
    let target = 1.0e8 + 2.1e-6 + i.to_double() * 1.7e-8
    let initial_error = target - 1.0e8
    let tolerance = initial_error * 0.999
    s.constrain(Fix(p, target, 0.0)) |> ignore
    let r = s
      .solve(options={ ..SolveOptions::default(), length_tolerance: tolerance, })
      .unwrap()
    if r.report.is_satisfied() {
      let actual_error = (r.point(p).unwrap().x - target).abs()
      assert_true(
        actual_error <= tolerance,
        msg="case \{i}: actual \{actual_error} exceeds \{tolerance}",
      )
    }
  }
}

///|
test "world validation avoids point line cross product underflow" {
  for scale in [1.0e-200, 1.0e-100, 1.0, 1.0e90] {
    let s = Sketch::new()
    let a = s.add_point(0.0, 0.0)
    let b = s.add_point(3.0 * scale, 4.0 * scale)
    let p = s.add_point(-4.0 * scale, 3.0 * scale)
    let l = s.add_line(a, b)
    s.constrain(Fix(a, 0.0, 0.0)) |> ignore
    s.constrain(Fix(b, 3.0 * scale, 4.0 * scale)) |> ignore
    s.constrain(Fix(p, -4.0 * scale, 3.0 * scale)) |> ignore
    let offset = s.constrain(DistanceToLine(p, l, 5.0 * scale))
    let options = {
      ..SolveOptions::default(),
      length_tolerance: 1.0e-8 * scale,
    }
    let r = solved(s, options~)
    assert_true(
      r.report.residual(offset).unwrap().length_error <=
      options.length_tolerance,
    )
    // Independent unit normal (-4/5, 3/5), without an unscaled cross product.
    near((-0.8 * sp(r, p).x + 0.6 * sp(r, p).y) / scale, 5.0, tol=1.0e-7)
  }
}
