///|
priv struct Dimensions {
  ground : Double
  crank : Double
  coupler : Double
  rocker : Double
}

///|
priv struct FourBar {
  sketch : @sketch.Sketch
  points : Array[@sketch.PointId]
  reference : @sketch.LineId
  crank_line : @sketch.LineId
  lengths : Array[@sketch.ConstraintId]
  drive : @sketch.ConstraintId
  dimensions : Dimensions
  upper : Bool
}

///|
fn demand(condition : Bool, message : String) -> Unit {
  if !condition {
    abort(message)
  }
}

///|
fn close_to(actual : Double, expected : Double) -> Unit {
  if actual.is_nan() || actual.is_inf() || (actual - expected).abs() > 5.0e-6 {
    abort("Four-bar value \{actual}; expected \{expected}")
  }
}

///|
fn radians(degrees : Int32) -> Double {
  degrees.to_double() * @math.PI / 180.0
}

///|
/// This example's parameter domain excludes circle tangencies and requires
/// ground > crank, leaving two separate assembly branches throughout a turn.
fn new_four_bar(dimensions : Dimensions, upper~ : Bool = true) -> FourBar {
  let p = dimensions
  for length in [p.ground, p.crank, p.coupler, p.rocker] {
    demand(
      !length.is_nan() && !length.is_inf() && length > 0.0,
      "Link lengths must be finite and positive",
    )
  }
  demand(
    p.ground > p.crank &&
    p.ground - p.crank > (p.coupler - p.rocker).abs() &&
    p.ground + p.crank < p.coupler + p.rocker,
    "Example dimensions must allow a nonsingular full crank turn",
  )
  let s = @sketch.Sketch::new()
  // Approximate seeds select an assembly branch. Subsequent frames never
  // assign point coordinates: the previous solution is the next initial guess.
  let a = s.add_point(0.0, 0.0)
  let b = s.add_point(p.crank * 0.98, p.crank * 0.02)
  let c = s.add_point(
    p.ground * 0.98,
    if upper {
      p.rocker * 0.98
    } else {
      -p.rocker * 0.98
    },
  )
  let d = s.add_point(p.ground, 0.0)
  let reference = s.add_line(a, d)
  let crank_line = s.add_line(a, b)
  s.add_line(b, c) |> ignore
  s.add_line(c, d) |> ignore
  s.constrain(Fix(a, 0.0, 0.0)) |> ignore
  s.constrain(Fix(d, p.ground, 0.0)) |> ignore
  let lengths = [
    s.constrain(Distance(a, b, p.crank)),
    s.constrain(Distance(b, c, p.coupler)),
    s.constrain(Distance(c, d, p.rocker)),
  ]
  let drive = s.constrain(Angle(reference, crank_line, 0.0))
  {
    sketch: s,
    points: [a, b, c, d],
    reference,
    crank_line,
    lengths,
    drive,
    dimensions,
    upper,
  }
}

///|
/// Analytic B and the two-circle intersection for C are an oracle only.
fn FourBar::verify(self : FourBar, degrees : Int32) -> Unit {
  let p = self.dimensions
  let a = self.sketch.point(self.points[0]).unwrap()
  let b = self.sketch.point(self.points[1]).unwrap()
  let c = self.sketch.point(self.points[2]).unwrap()
  let d = self.sketch.point(self.points[3]).unwrap()
  let bx = p.crank * @math.cos(radians(degrees))
  let by = p.crank * @math.sin(radians(degrees))
  let dx = p.ground - bx
  let dy = -by
  let base = @math.hypot(dx, dy)
  let along = (p.coupler * p.coupler - p.rocker * p.rocker + base * base) /
    (2.0 * base)
  let height = (p.coupler * p.coupler - along * along).sqrt()
  let sign = if self.upper { 1.0 } else { -1.0 }
  let cx = bx + along * dx / base - sign * height * dy / base
  let cy = by + along * dy / base + sign * height * dx / base
  close_to(a.x, 0.0)
  close_to(a.y, 0.0)
  close_to(d.x, p.ground)
  close_to(d.y, 0.0)
  close_to(b.x, bx)
  close_to(b.y, by)
  close_to(c.x, cx)
  close_to(c.y, cy)
  close_to(@math.hypot(b.x - a.x, b.y - a.y), p.crank)
  close_to(@math.hypot(c.x - b.x, c.y - b.y), p.coupler)
  close_to(@math.hypot(d.x - c.x, d.y - c.y), p.rocker)
  demand(
    sign * ((d.x - b.x) * (c.y - b.y) - (d.y - b.y) * (c.x - b.x)) > 0.0,
    "Assembly branch changed",
  )
}

///|
fn FourBar::advance(self : FourBar, degrees : Int32) -> @sketch.Solution {
  demand(
    self.sketch.set_constraint(
      self.drive,
      Angle(self.reference, self.crank_line, radians(degrees)),
    ),
    "Missing crank angle constraint",
  )
  let solution = match self.sketch.solve_and_apply() {
    Ok(solution) => solution
    Err(error) => abort(error.message())
  }
  demand(
    solution.report.is_satisfied() &&
    solution.report.local_dof == 0 &&
    solution.report.variables == 8 &&
    solution.report.equations == 8 &&
    solution.report.dependent_equations == 0,
    "Driven four-bar pose must be satisfied and locally fully constrained",
  )
  self.verify(degrees)
  solution
}

///|
/// Inspect the undriven system without applying a different configuration.
fn FourBar::free_dof(self : FourBar) -> Int32 {
  demand(
    self.sketch.set_constraint_enabled(self.drive, false),
    "Cannot disable crank drive",
  )
  let solution = match self.sketch.solve() {
    Ok(solution) => solution
    Err(error) => abort(error.message())
  }
  demand(
    solution.report.is_satisfied() &&
    solution.report.equations == 7 &&
    solution.report.local_dof == 1,
    "Undriven four-bar should have one local degree of freedom",
  )
  demand(
    self.sketch.set_constraint_enabled(self.drive, true),
    "Cannot restore crank drive",
  )
  solution.report.local_dof
}

///|
fn FourBar::emit(
  self : FourBar,
  index : Int32,
  degrees : Int32,
  direction : String,
  solution : @sketch.Solution,
) -> Unit {
  let report = solution.report
  let mut points = "["
  for i, id in self.points {
    if i > 0 {
      points = points + ","
    }
    let point = self.sketch.point(id).unwrap()
    points = points + "[\{point.x},\{point.y}]"
  }
  points = points + "]"
  let mut residuals = "["
  for i, residual in report.residuals {
    if i > 0 {
      residuals = residuals + ","
    }
    residuals = residuals +
      "{\"id\":\{residual.id.index()},\"active\":\{residual.active},\"length_error\":\{residual.length_error},\"angular_error\":\{residual.angular_error},\"tolerance_ratio\":\{residual.tolerance_ratio}}"
  }
  residuals = residuals + "]"
  println(
    "{\"kind\":\"pose\",\"index\":\{index},\"degrees\":\{degrees},\"direction\":\"\{direction}\",\"points\":\{points},\"constraint_ids\":{\"AB\":\{self.lengths[0].index()},\"BC\":\{self.lengths[1].index()},\"CD\":\{self.lengths[2].index()},\"drive\":\{self.drive.index()}},\"report\":{\"status\":\"Satisfied\",\"variables\":\{report.variables},\"equations\":\{report.equations},\"local_dof\":\{report.local_dof},\"iterations\":\{report.iterations},\"max_tolerance_ratio\":\{report.max_tolerance_ratio},\"residuals\":\{residuals}}}",
  )
}

///|
fn main {
  let p : Dimensions = {
    ground: 80.0,
    crank: 30.0,
    coupler: 70.0,
    rocker: 50.0,
  }
  let mechanism = new_four_bar(p)
  let first = mechanism.advance(0)
  let free = mechanism.free_dof()
  println(
    "{\"kind\":\"mechanism\",\"lengths\":{\"AD\":\{p.ground},\"AB\":\{p.crank},\"BC\":\{p.coupler},\"CD\":\{p.rocker}},\"upper_assembly\":true,\"free_local_dof\":\{free},\"pose_count\":25}",
  )
  mechanism.emit(0, 0, "forward", first)
  for step = 1; step <= 12; step = step + 1 {
    let degrees = step * 15
    mechanism.emit(step, degrees, "forward", mechanism.advance(degrees))
  }
  for step = 1; step <= 12; step = step + 1 {
    let degrees = 180 - step * 15
    mechanism.emit(12 + step, degrees, "reverse", mechanism.advance(degrees))
  }
}
