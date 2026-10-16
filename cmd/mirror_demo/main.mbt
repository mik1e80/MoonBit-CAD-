///|
fn require_solved(s : @sketch.Sketch) -> @sketch.Solution {
  match s.solve_and_apply() {
    Ok(r) => {
      if !r.report.is_satisfied() || r.report.local_dof != 0 {
        abort("Mirror example did not reach a fully constrained solution")
      }
      r
    }
    Err(e) => abort(e)
  }
}

///|
fn require_near(value : Double, expected : Double) -> Unit {
  if (value - expected).abs() > 1.0e-5 {
    abort("Unexpected geometry: \{value}; expected \{expected}")
  }
}

///|
fn main {
  let s = @sketch.Sketch::new()
  let bottom = s.add_point(10.0, 0.0)
  let top = s.add_point(10.0, 10.0)
  let left = s.add_point(6.0, 3.0)
  let right = s.add_point(13.0, 2.5)
  let axis = s.add_line(bottom, top)
  let left_hole = s.add_circle(left, 2.0)
  let right_hole = s.add_circle(right, 1.5)
  let bottom_fix = s.constrain(Fix(bottom, 10.0, 0.0))
  let top_fix = s.constrain(Fix(top, 10.0, 10.0))
  s.constrain(Fix(left, 6.0, 3.0)) |> ignore
  s.constrain(Mirror(left, right, axis)) |> ignore
  s.constrain(Radius(left_hole, 2.0)) |> ignore
  s.constrain(EqualRadius(left_hole, right_hole)) |> ignore
  let first = require_solved(s)
  require_near(first.point(right).unwrap().x, 14.0)
  require_near(first.point(right).unwrap().y, 3.0)
  require_near(first.radius(right_hole).unwrap(), 2.0)
  println("Mirrored holes: centers=(6,3),(14,3); radii=2")

  s.set_constraint(bottom_fix, Fix(bottom, 12.0, 0.0)) |> ignore
  s.set_constraint(top_fix, Fix(top, 12.0, 10.0)) |> ignore
  let shifted = require_solved(s)
  require_near(shifted.point(right).unwrap().x, 18.0)
  require_near(shifted.point(right).unwrap().y, 3.0)
  println("Axis moved to x=12: reflected center=(18,3)")

  let previous = s.point(right).unwrap()
  let conflict = s.constrain(Fix(right, 0.0, 0.0))
  match s.solve_and_apply() {
    Ok(r) =>
      if r.report.is_satisfied() {
        abort("Expected conflicting edit to fail")
      }
    Err(e) => abort(e)
  }
  let retained = s.point(right).unwrap()
  if retained.x != previous.x || retained.y != previous.y {
    abort("Failed mirror edit changed geometry")
  }
  s.set_constraint_enabled(conflict, false) |> ignore
  require_solved(s) |> ignore
  println("Conflicting edit rejected; geometry retained and relation recovered")
}
