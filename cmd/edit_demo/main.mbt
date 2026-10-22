///|
fn require(
  result : Result[@sketch.Solution, @sketch.SketchError],
  satisfied : Bool,
) -> @sketch.Solution {
  let r = match result {
    Ok(r) => r
    Err(e) => abort(e.message())
  }
  if r.report.is_satisfied() != satisfied {
    abort("Unexpected convergence state in editing example")
  }
  if satisfied && r.report.local_dof != 0 {
    abort("Editing example should be fully constrained")
  }
  r
}

///|
fn check_coordinate(value : Double, expected : Double) -> Unit {
  if (value - expected).abs() > 1.0e-5 {
    abort("Unexpected coordinate: \{value}; expected \{expected}")
  }
}

///|
fn main {
  let s = @sketch.Sketch::new()
  let origin = s.add_point(0.0, 0.0)
  let left = s.add_point(-4.4, 2.1)
  let right = s.add_point(4.5, -1.8)
  let a = s.add_point(-10.0, -5.0)
  let b = s.add_point(10.0, -5.0)
  let center = s.add_point(3.0, 3.8)
  let baseline = s.add_line(a, b)
  let spoke = s.add_line(origin, left)
  let outer = s.add_circle(origin, 7.0)
  let inner = s.add_circle(center, 2.0)
  s.constrain(Fix(origin, 0.0, 0.0)) |> ignore
  s.constrain(Fix(a, -10.0, -5.0)) |> ignore
  s.constrain(Fix(b, 10.0, -5.0)) |> ignore
  s.constrain(Symmetric(left, right, origin)) |> ignore
  let offset = s.constrain(DistanceToLine(left, baseline, 7.0))
  let ratio = s.constrain(LengthRatio(spoke, baseline, 0.25))
  s.constrain(Radius(outer, 7.0)) |> ignore
  s.constrain(Radius(inner, 2.0)) |> ignore
  s.constrain(InternalTangent(outer, inner)) |> ignore
  s.constrain(DistanceX(origin, center, 3.0)) |> ignore
  let conflict = s.constrain(Fix(left, 9.0, 9.0))
  s.set_constraint_enabled(conflict, false) |> ignore
  let first = require(s.solve_and_apply(), true)
  let p = first.point(left).unwrap()
  check_coordinate(p.x, -21.0.sqrt())
  check_coordinate(p.y, 2.0)
  check_coordinate(first.point(right).unwrap().x, 21.0.sqrt())
  check_coordinate(first.point(center).unwrap().y, 4.0)
  println(
    "Initial sketch: satisfied; symmetry, offset, ratio, and internal tangency verified",
  )

  s.set_constraint_enabled(conflict, true) |> ignore
  let failed = require(s.solve_and_apply(), false)
  let retained = s.point(left).unwrap()
  if retained.x != p.x || retained.y != p.y {
    abort("Failed editing solve changed the sketch")
  }
  for finding in failed.report.unsatisfied() {
    if s.constraint(finding.id) is None {
      abort("Missing diagnostic relation")
    }
  }
  println("Conflicting edit: rejected; previous geometry retained")

  s.set_constraint_enabled(conflict, false) |> ignore
  s.set_constraint(offset, DistanceToLine(left, baseline, 6.0)) |> ignore
  s.set_constraint(ratio, LengthRatio(spoke, baseline, 0.3)) |> ignore
  s.set_radius(outer, 8.0) |> ignore
  let revised = require(s.solve_and_apply(), true)
  let p = revised.point(left).unwrap()
  check_coordinate(p.x, -35.0.sqrt())
  check_coordinate(p.y, 1.0)
  check_coordinate(revised.point(right).unwrap().y, -1.0)
  check_coordinate(revised.radius(outer).unwrap(), 7.0)
  println(
    "Revised dimensions: satisfied; left=(\{p.x}, \{p.y}); original constraint IDs retained",
  )
}
