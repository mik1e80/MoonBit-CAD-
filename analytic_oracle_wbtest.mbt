///|
test "seeded triangles agree with analytic circle intersections after transforms" {
  for i = 0; i < 64; i = i + 1 {
    let scale = [1.0e-4, 1.0, 1.0e4][i % 3]
    let side_a = 2.0 + i.to_double() * 0.13
    let side_b = 3.0 + (i % 7).to_double() * 0.17
    let shorter = if side_a < side_b { side_a } else { side_b }
    let base = (side_a - side_b).abs() + 1.2 * shorter
    let along = (side_a * side_a + base * base - side_b * side_b) / (2.0 * base)
    let height = (side_a * side_a - along * along).sqrt()
    let angle = i.to_double() * 0.137 - 3.0
    let co = @math.cos(angle)
    let si = @math.sin(angle)
    let ox = (i - 24).to_double() * 20000.0 * scale
    let oy = -i.to_double() * 13000.0 * scale
    let bx = ox + base * co * scale
    let by = oy + base * si * scale
    let expected_x = ox + (along * co - height * si) * scale
    let expected_y = oy + (along * si + height * co) * scale
    let s = Sketch::new()
    let a = s.add_point(ox, oy)
    let b = s.add_point(bx + 0.03 * scale, by - 0.02 * scale)
    let c = s.add_point(expected_x + 0.05 * scale, expected_y - 0.04 * scale)
    s.constrain(Fix(a, ox, oy)) |> ignore
    s.constrain(Fix(b, bx, by)) |> ignore
    s.constrain(Distance(a, c, side_a * scale)) |> ignore
    s.constrain(Distance(b, c, side_b * scale)) |> ignore
    let tolerance = 1.0e-7 * scale
    let r = solved(s, options={
      ..SolveOptions::default(),
      length_tolerance: tolerance,
    })
    let actual_a = sp(r, a)
    let actual_b = sp(r, b)
    let actual_c = sp(r, c)
    assert_eq(r.report.local_dof, 0)
    near(actual_c.x, expected_x, tol=20.0 * tolerance)
    near(actual_c.y, expected_y, tol=20.0 * tolerance)
    near(distance(actual_a, actual_c), side_a * scale, tol=tolerance)
    near(distance(actual_b, actual_c), side_b * scale, tol=tolerance)
    near(actual_a.x, ox, tol=tolerance)
    near(actual_a.y, oy, tol=tolerance)
    near(actual_b.x, bx, tol=tolerance)
    near(actual_b.y, by, tol=tolerance)
  }
}

///|
test "derivatives stay accurate at several non singular configurations" {
  for phase in [0.1, 0.6, 1.1, 1.6] {
    let s = Sketch::new()
    let a = s.add_point(0.3, -0.4)
    let b = s.add_point(3.0 * @math.cos(phase), 3.0 * @math.sin(phase))
    let c = s.add_point(-1.2, 2.7)
    let d = s.add_point(2.1, -1.4)
    let ab = s.add_line(a, b)
    let cd = s.add_line(c, d)
    let outer = s.add_circle(a, 3.0)
    let inner = s.add_circle(c, 1.0)
    for
      relation in [
        Angle(ab, cd, -0.4),
        Parallel(ab, cd),
        Perpendicular(ab, cd),
        DistanceToLine(d, ab, 2.0),
        LengthRatio(ab, cd, 0.7),
        Tangent(ab, inner),
        InternalTangent(outer, inner),
      ] {
      s.constrain(relation) |> ignore
    }
    let frame = s.frame()
    let x = s.parameters(frame)
    let rows = s.evaluate(x, frame).unwrap()
    for k = 0; k < x.length(); k = k + 1 {
      let xp = x.copy()
      let xm = x.copy()
      xp[k] = xp[k] + 1.0e-6
      xm[k] = xm[k] - 1.0e-6
      let rp = s.evaluate(xp, frame).unwrap()
      let rm = s.evaluate(xm, frame).unwrap()
      for j = 0; j < rows.length(); j = j + 1 {
        near(rows[j].jet.d[k], (rp[j].jet.v - rm[j].jet.v) / 2.0e-6, tol=2.0e-7)
      }
    }
  }
}
