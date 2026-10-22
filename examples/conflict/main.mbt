///|
fn solve(s : @sketch.Sketch) -> @sketch.Solution {
  match s.solve_and_apply() {
    Ok(solution) => solution
    Err(error) => abort(error.message())
  }
}

///|
fn demand(condition : Bool, message : String) -> Unit {
  if !condition {
    abort(message)
  }
}

///|
fn main {
  let sketch = @sketch.Sketch::new()
  let p = sketch.add_point(2.0, 3.0)
  sketch.constrain(Fix(p, 0.0, 0.0)) |> ignore
  let conflict = sketch.constrain(Fix(p, 10.0, 0.0))
  let failed = solve(sketch)
  demand(!failed.report.is_satisfied(), "Expected conflicting positions")
  let stored = sketch.point(p).unwrap()
  demand(stored.x == 2.0 && stored.y == 3.0, "Failed solve modified geometry")
  let findings = failed.report.likely_conflicts()
  demand(findings.length() > 0, "Expected unsatisfied diagnostics")
  println("Conflicting edit: geometry retained at (2,3)")
  for finding in findings {
    println(
      "constraint #\{finding.id.index()}: error ratio=\{finding.tolerance_ratio}",
    )
  }
  demand(sketch.set_constraint_enabled(conflict, false), "Disable failed")
  demand(solve(sketch).report.is_satisfied(), "Disable did not recover")
  demand(sketch.set_constraint_enabled(conflict, true), "Enable failed")
  demand(
    !solve(sketch).report.is_satisfied(),
    "Expected conflict after enabling",
  )
  demand(sketch.remove_constraint(conflict), "Remove failed")
  let recovered = solve(sketch)
  demand(recovered.report.is_satisfied(), "Removal did not recover")
  demand(sketch.constraint(conflict) is None, "Removed relation still exists")
  let point = sketch.point(p).unwrap()
  demand(
    point.x.abs() < 1.0e-6 && point.y.abs() < 1.0e-6,
    "Wrong recovered position",
  )
  println("Disabled then removed conflicting relation; recovered near (0,0)")
}
