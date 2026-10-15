///|
pub(all) enum SolveStatus {
  Satisfied
  Stalled
  IterationLimit
} derive(Debug)

///|
pub extend SolveStatus with @debug.Debug::{to_repr}

///|
pub(all) struct SolveOptions {
  length_tolerance : Double
  angular_tolerance : Double
  rank_tolerance : Double
  max_iterations : Int32
}

///|
pub fn SolveOptions::default() -> SolveOptions {
  {
    length_tolerance: 1.0e-7,
    angular_tolerance: 1.0e-8,
    rank_tolerance: 1.0e-9,
    max_iterations: 200,
  }
}

///|
/// Maximum component errors per constraint, before tolerance weighting.
pub struct ConstraintResidual {
  id : ConstraintId
  active : Bool
  length_error : Double
  angular_error : Double
  tolerance_ratio : Double
} derive(Debug)

///|
pub extend ConstraintResidual with @debug.Debug::{to_repr}

///|
/// DOF and equation dependence refer to the local Jacobian at this result.
/// Unsatisfied constraints are symptoms, not a proven minimal conflict set.
pub struct SolveReport {
  priv owner : Array[Unit]
  status : SolveStatus
  iterations : Int32
  variables : Int32
  equations : Int32
  rank : Int32
  local_dof : Int32
  dependent_equations : Int32
  max_tolerance_ratio : Double
  residuals : Array[ConstraintResidual]
} derive(Debug)

///|
pub extend SolveReport with @debug.Debug::{to_repr}

///|
pub struct Solution {
  priv owner : Array[Unit]
  report : SolveReport
  priv points : Array[Point]
  priv radii : Array[Double]
}

///|
pub fn Solution::point(self : Solution, id : PointId) -> Point? {
  if physical_equal(self.owner, id.owner) {
    self.points.get(id.index)
  } else {
    None
  }
}

///|
pub fn Solution::radius(self : Solution, id : CircleId) -> Double? {
  if physical_equal(self.owner, id.owner) {
    self.radii.get(id.index)
  } else {
    None
  }
}

///|
pub fn SolveReport::is_satisfied(self : SolveReport) -> Bool {
  match self.status {
    Satisfied => true
    _ => false
  }
}

///|
pub fn SolveReport::unsatisfied(
  self : SolveReport,
) -> Array[ConstraintResidual] {
  self.residuals.filter(r => r.active && r.tolerance_ratio > 1.0)
}

///|
/// Identifiers refer to the sketch at solve time, including satisfied relations.
pub fn SolveReport::residual(
  self : SolveReport,
  id : ConstraintId,
) -> ConstraintResidual? {
  if physical_equal(self.owner, id.owner) {
    self.residuals.get(id.index)
  } else {
    None
  }
}

///|
fn row_tolerance(row : Row, frame : Frame, options : SolveOptions) -> Double {
  if row.angular {
    options.angular_tolerance
  } else {
    options.length_tolerance / frame.scale
  }
}

///|
fn weighted_system(
  rows : Array[Row],
  frame : Frame,
  options : SolveOptions,
) -> (Array[Double], Array[Array[Double]]) {
  let residual = rows.map(r => r.jet.v / row_tolerance(r, frame, options))
  let jacobian = rows.map(r => {
    r.jet.d.map(d => d / row_tolerance(r, frame, options))
  })
  (residual, jacobian)
}

///|
fn cost(residual : Array[Double]) -> Double {
  let mut value = 0.0
  for r in residual {
    value = value + r * r
  }
  value
}

///|
fn Sketch::solution(
  self : Sketch,
  x : Array[Double],
  frame : Frame,
  options : SolveOptions,
  status : SolveStatus,
  iterations : Int32,
) -> Result[Solution, String] {
  let points : Array[Point] = Array::makei(self.points.length(), i => {
    x: x[i * 2] * frame.scale + frame.x,
    y: x[i * 2 + 1] * frame.scale + frame.y,
  })
  let radii = Array::makei(self.circles.length(), i => {
    x[self.points.length() * 2 + i] * frame.scale
  })
  if points.any(p => !finite(p.x) || !finite(p.y)) || radii.any(r => !finite(r)) {
    return Err("Output geometry overflow")
  }
  // Re-evaluate the actual returned Double coordinates after denormalization.
  // A large origin can lose small dimensions; normalized convergence alone
  // must not result in a false success for the returned geometry.
  let physical_x = []
  for p in points {
    physical_x.push((p.x - frame.x) / frame.scale)
    physical_x.push((p.y - frame.y) / frame.scale)
  }
  for r in radii {
    physical_x.push(r / frame.scale)
  }
  let rows = match self.evaluate(physical_x, frame) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  let length_errors = Array::make(self.constraints.length(), 0.0)
  let angular_errors = Array::make(self.constraints.length(), 0.0)
  let ratios = Array::make(self.constraints.length(), 0.0)
  for row in rows {
    let i = row.constraint
    let error = row.jet.v.abs()
    if row.angular {
      angular_errors[i] = dmax(angular_errors[i], error)
    } else {
      length_errors[i] = dmax(length_errors[i], error * frame.scale)
    }
    ratios[i] = dmax(ratios[i], error / row_tolerance(row, frame, options))
  }
  let rank = numerical_rank(
    rows.map(r => r.jet.d),
    x.length(),
    options.rank_tolerance,
  )
  let residuals = Array::makei(self.constraints.length(), i => {
    id: self.constraint_id(i),
    active: self.enabled[i],
    length_error: length_errors[i],
    angular_error: angular_errors[i],
    tolerance_ratio: ratios[i],
  })
  let status = if max_abs(ratios) <= 1.0 {
    Satisfied
  } else {
    match status {
      Satisfied => Stalled
      other => other
    }
  }
  let report : SolveReport = {
    owner: self.owner,
    status,
    iterations,
    variables: x.length(),
    equations: rows.length(),
    rank,
    local_dof: x.length() - rank,
    dependent_equations: rows.length() - rank,
    max_tolerance_ratio: max_abs(ratios),
    residuals,
  }
  Ok({ owner: self.owner, report, points, radii, })
}

///|
/// Local damped Gauss-Newton solve, with an exact forward-AD Jacobian.
/// Err means invalid input/evaluation, not a mathematical proof of inconsistency.
/// A nonconverged Solution still contains the best accepted iterate for inspection.
pub fn Sketch::solve(
  self : Sketch,
  options~ : SolveOptions = SolveOptions::default(),
) -> Result[Solution, String] {
  match self.validate() {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  if !finite(options.length_tolerance) ||
    options.length_tolerance <= 0.0 ||
    !finite(options.angular_tolerance) ||
    options.angular_tolerance < 1.0e-14 ||
    options.angular_tolerance > 0.1 ||
    !finite(options.rank_tolerance) ||
    options.rank_tolerance < 1.0e-14 ||
    options.rank_tolerance > 0.01 ||
    options.max_iterations < 1 ||
    options.max_iterations > 1000 {
    return Err("Invalid tolerances or iteration budget (1..1000)")
  }
  let frame = self.frame()
  let relative_tolerance = options.length_tolerance / frame.scale
  if !finite(relative_tolerance) ||
    relative_tolerance < 1.0e-14 ||
    relative_tolerance > 1.0e6 {
    return Err("Length tolerance / sketch scale must be between 1e-14 and 1e6")
  }
  let mut x = self.parameters(frame)
  let mut rows = match self.evaluate(x, frame) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  let mut lambda = 1.0e-3
  for iteration = 0
      iteration < options.max_iterations
      iteration = iteration + 1 {
    let (residual, jacobian) = weighted_system(rows, frame, options)
    if max_abs(residual) <= 1.0 {
      return self.solution(x, frame, options, Satisfied, iteration)
    }
    let old_cost = cost(residual)
    let mut accepted = false
    for attempt = 0; attempt < 16; attempt = attempt + 1 {
      let delta = match damped_step(jacobian, residual, x.length(), lambda) {
        Some(d) => d
        None => {
          lambda = lambda * 10.0
          continue
        }
      }
      if max_abs(delta) <= 1.0e-14 {
        break
      }
      let trial = Array::makei(x.length(), i => x[i] + delta[i])
      match self.evaluate(trial, frame) {
        Ok(trial_rows) => {
          let (trial_residual, _) = weighted_system(trial_rows, frame, options)
          if cost(trial_residual) < old_cost {
            x = trial
            rows = trial_rows
            lambda = dmax(lambda * 0.25, 1.0e-12)
            accepted = true
            break
          }
        }
        Err(_) => ()
      }
      lambda = lambda * 10.0
    }
    if !accepted {
      return self.solution(x, frame, options, Stalled, iteration + 1)
    }
  }
  let (residual, _) = weighted_system(rows, frame, options)
  let status = if max_abs(residual) <= 1.0 { Satisfied } else { IterationLimit }
  self.solution(x, frame, options, status, options.max_iterations)
}

///|
/// Commit geometry only if all residuals meet tolerance. Failed solves are atomic.
pub fn Sketch::solve_and_apply(
  self : Sketch,
  options~ : SolveOptions = SolveOptions::default(),
) -> Result[Solution, String] {
  let solution = match self.solve(options~) {
    Ok(s) => s
    Err(e) => return Err(e)
  }
  if solution.report.is_satisfied() {
    for i, p in solution.points {
      self.points[i] = p
    }
    for i, r in solution.radii {
      let c = self.circles[i]
      self.circles[i] = { center: c.center, radius: r, }
    }
  }
  Ok(solution)
}
