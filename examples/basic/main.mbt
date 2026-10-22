///|
fn report(
  name : String,
  result : Result[@sketch.Solution, @sketch.SketchError],
) -> @sketch.Solution? {
  match result {
    Err(e) => {
      println("\{name}: input error: \{e.message()}")
      None
    }
    Ok(s) => {
      let r = s.report
      let status = match r.status {
        Satisfied => "satisfied"
        Stalled => "stalled"
        IterationLimit => "iteration limit"
      }
      println(
        "\{name}: \{status}; local DOF=\{r.local_dof}; iterations=\{r.iterations}; max tolerance ratio=\{r.max_tolerance_ratio}",
      )
      Some(s)
    }
  }
}

///|
fn rectangle() -> Unit {
  let s = @sketch.Sketch::new()
  let a = s.add_point(0.2, -0.1)
  let b = s.add_point(9.5, 0.4)
  let c = s.add_point(10.8, 5.4)
  let d = s.add_point(-0.3, 6.3)
  let ab = s.add_line(a, b)
  let bc = s.add_line(b, c)
  let cd = s.add_line(c, d)
  let da = s.add_line(d, a)
  s.constrain(Fix(a, 0.0, 0.0)) |> ignore
  s.constrain(Horizontal(ab)) |> ignore
  s.constrain(Horizontal(cd)) |> ignore
  s.constrain(Vertical(bc)) |> ignore
  s.constrain(Vertical(da)) |> ignore
  let width = s.constrain(DistanceX(a, b, 10.0))
  s.constrain(DistanceY(b, c, 6.0)) |> ignore
  match report("rectangle 10x6", s.solve_and_apply()) {
    Some(r) =>
      for p in [a, b, c, d] {
        let point = r.point(p).unwrap()
        println("  (\{point.x}, \{point.y})")
      }
    None => ()
  }
  s.set_constraint(width, DistanceX(a, b, 15.0)) |> ignore
  report("rectangle resized to 15x6", s.solve_and_apply()) |> ignore
}

///|
fn triangle() -> Unit {
  let s = @sketch.Sketch::new()
  let a = s.add_point(0.0, 0.0)
  let b = s.add_point(4.5, 0.3)
  let c = s.add_point(2.0, 2.2)
  s.constrain(Fix(a, 0.0, 0.0)) |> ignore
  s.constrain(Horizontal(s.add_line(a, b))) |> ignore
  s.constrain(Distance(a, b, 5.0)) |> ignore
  s.constrain(Distance(a, c, 3.0)) |> ignore
  s.constrain(Distance(b, c, 4.0)) |> ignore
  match report("3-4-5 triangle", s.solve()) {
    Some(r) => {
      let p = r.point(c).unwrap()
      println("  expected C=(1.8, 2.4); actual C=(\{p.x}, \{p.y})")
    }
    None => ()
  }
}

///|
fn tangent() -> Unit {
  let s = @sketch.Sketch::new()
  let a = s.add_point(0.0, 0.0)
  let b = s.add_point(4.0, 1.0)
  let c = s.add_circle(a, 2.5)
  let d = s.add_circle(b, 1.5)
  s.constrain(Fix(a, 0.0, 0.0)) |> ignore
  s.constrain(DistanceY(a, b, 0.0)) |> ignore
  s.constrain(Radius(c, 3.0)) |> ignore
  s.constrain(Radius(d, 2.0)) |> ignore
  s.constrain(ExternalTangent(c, d)) |> ignore
  report("externally tangent circles", s.solve()) |> ignore
}

///|
fn impossible() -> Unit {
  let s = @sketch.Sketch::new()
  let p = s.add_point(0.0, 0.0)
  s.constrain(Fix(p, 0.0, 0.0)) |> ignore
  s.constrain(Fix(p, 10.0, 0.0)) |> ignore
  match report("contradictory positions", s.solve()) {
    Some(r) =>
      for residual in r.report.unsatisfied() {
        println(
          "  constraint \{residual.id.index()}: length error=\{residual.length_error}",
        )
      }
    None => ()
  }
}

///|
fn main {
  rectangle()
  triangle()
  tangent()
  impossible()
}
