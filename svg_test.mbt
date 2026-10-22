///|
test "svg supports an empty sketch and defaults without mutation" {
  let s = @sketch.Sketch::new()
  let svg = s.to_svg().unwrap()
  assert_true(svg.contains("viewBox=\"0 0 720 440\""))
  assert_true(svg.contains("<title>CAD sketch</title>"))
  assert_false(svg.contains("data-point="))
}

///|
test "svg maps points and line endpoints with Y pointing up" {
  let s = @sketch.Sketch::new()
  let a = s.add_point(-1.0, -1.0)
  let b = s.add_point(1.0, 1.0)
  s.add_line(a, b) |> ignore
  let svg = s
    .to_svg(options={
      ..@sketch.SvgOptions::default(),
      width: 200,
      height: 232,
      padding: 10.0,
      bounds: Some({ min_x: -1.0, min_y: -1.0, max_x: 1.0, max_y: 1.0, }),
    })
    .unwrap()
  assert_true(svg.contains("x1=\"10\" y1=\"222\" x2=\"190\" y2=\"42\""))
  assert_eq(s.point(a).unwrap().x, -1.0)
  assert_eq(s.point(b).unwrap().y, 1.0)
}

///|
test "svg circles keep radius and markers can be hidden" {
  let s = @sketch.Sketch::new()
  let p = s.add_point(0.0, 0.0)
  s.add_circle(p, 2.0) |> ignore
  let svg = s
    .to_svg(options={
      ..@sketch.SvgOptions::default(),
      width: 200,
      height: 232,
      padding: 10.0,
      show_points: false,
    })
    .unwrap()
  assert_true(svg.contains("data-circle=\"0\" cx=\"100\" cy=\"132\" r=\"90\""))
  assert_false(svg.contains("data-point="))
}

///|
test "svg title escapes markup and invalid XML characters" {
  let s = @sketch.Sketch::new()
  let svg = s
    .to_svg(options={
      ..@sketch.SvgOptions::default(),
      title: "A<&\"'>\u0000\uFFFE\n孔",
    })
    .unwrap()
  assert_true(svg.contains("A&lt;&amp;&quot;&apos;&gt;�� 孔"))
  assert_false(svg.contains("\u0000"))
  assert_false(svg.contains("\uFFFE"))
}

///|
test "svg rejects invalid dimensions and clipping bounds" {
  let s = @sketch.Sketch::new()
  s.add_point(5.0, 5.0) |> ignore
  for
    options in [
      { ..@sketch.SvgOptions::default(), width: 0, },
      { ..@sketch.SvgOptions::default(), padding: 1.0 / 0.0, },
      { ..@sketch.SvgOptions::default(), padding: 400.0, },
      {
        ..@sketch.SvgOptions::default(),
        bounds: Some({ min_x: 0.0, min_y: 0.0, max_x: 1.0, max_y: 1.0, }),
      },
      {
        ..@sketch.SvgOptions::default(),
        bounds: Some({ min_x: 1.0, min_y: 0.0, max_x: 1.0, max_y: 6.0, }),
      },
    ] {
    assert_true(s.to_svg(options~) is Err(InvalidOptions(_)))
  }
}

///|
test "svg preserves normal geometry and constraint validation errors" {
  let s = @sketch.Sketch::new()
  let p = s.add_point(0.0, 0.0)
  let circle = s.add_circle(p, -1.0)
  assert_true(s.to_svg() is Err(InvalidRadius(id)) && id.index == circle.index)
  let other = @sketch.Sketch::new()
  let s = @sketch.Sketch::new()
  let p = s.add_point(0.0, 0.0)
  let foreign = s.constrain(Fix(other.add_point(1.0, 1.0), 0.0, 0.0))
  assert_true(s.to_svg() is Err(ForeignHandle))
  assert_true(s.set_constraint_enabled(foreign, false))
  assert_true(s.to_svg().unwrap().contains("data-point=\"0\""))
  assert_eq(s.point(p).unwrap().x, 0.0)
}

///|
test "svg handles tiny circles and isolated extreme coordinates" {
  for value in [1.0e-100, 1.0e100] {
    let s = @sketch.Sketch::new()
    let p = s.add_point(value, value)
    s.add_circle(p, 1.0e-100) |> ignore
    let svg = s.to_svg().unwrap()
    assert_false(svg.contains("NaN"))
    assert_false(svg.contains("Infinity"))
  }
}

///|
test "svg bounds contain actual radii even when coordinate addition rounds" {
  let s = @sketch.Sketch::new()
  let p = s.add_point(1.0e100, 1.0e100)
  s.add_circle(p, 1.0) |> ignore
  assert_true(
    s.to_svg(options={
      ..@sketch.SvgOptions::default(),
      bounds: Some({
        min_x: 1.0e100,
        min_y: 1.0e100,
        max_x: 1.0e100 + 1.0e90,
        max_y: 1.0e100 + 1.0e90,
      }),
    })
    is Err(InvalidOptions(_)),
  )
}

///|
test "svg exports retained geometry after conflicting solve" {
  let s = @sketch.Sketch::new()
  let a = s.add_point(0.0, 0.0)
  let b = s.add_point(5.0, 0.0)
  let line = s.add_line(a, b)
  s.constrain(Fix(a, 0.0, 0.0)) |> ignore
  s.constrain(Horizontal(line)) |> ignore
  s.constrain(Distance(a, b, 5.0)) |> ignore
  let before = s.to_svg().unwrap()
  s.constrain(Distance(a, b, 7.0)) |> ignore
  assert_false(s.solve_and_apply().unwrap().report.is_satisfied())
  assert_eq(s.to_svg().unwrap(), before)
}
