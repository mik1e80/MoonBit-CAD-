///|
priv struct Parameters {
  width : Double
  height : Double
  hole_radius : Double
  horizontal_margin : Double
  vertical_margin : Double
}

///|
/// All geometry and relation handles survive edits on this one sketch.
priv struct Bracket {
  sketch : @sketch.Sketch
  corners : Array[@sketch.PointId]
  axis_points : Array[@sketch.PointId]
  centers : Array[@sketch.PointId]
  holes : Array[@sketch.CircleId]
  width : @sketch.ConstraintId
  height : @sketch.ConstraintId
  radius : @sketch.ConstraintId
  horizontal_margin : @sketch.ConstraintId
  vertical_margin : @sketch.ConstraintId
  conflict : @sketch.ConstraintId
}

///|
fn require_true(value : Bool, message : String) -> Unit {
  if !value {
    abort(message)
  }
}

///|
fn near(value : Double, expected : Double) -> Unit {
  if value.is_nan() || value.is_inf() || (value - expected).abs() > 1.0e-5 {
    abort("Bracket geometry \{value}; expected \{expected}")
  }
}

///|
/// The demo accepts separated holes inside the plate. This is an application
/// input check, not an inequality constraint implemented by the core solver.
fn validate_parameters(p : Parameters) -> Unit {
  for
    value in [
      p.width,
      p.height,
      p.hole_radius,
      p.horizontal_margin,
      p.vertical_margin,
    ] {
    require_true(
      !value.is_nan() && !value.is_inf() && value > 0.0,
      "Bracket parameters must be finite and positive",
    )
  }
  require_true(
    p.horizontal_margin > p.hole_radius &&
    p.vertical_margin > p.hole_radius &&
    p.width > 2.0 * (p.horizontal_margin + p.hole_radius) &&
    p.height > 2.0 * (p.vertical_margin + p.hole_radius),
    "Demo holes must stay inside the plate and separated",
  )
}

///|
fn new_bracket(p : Parameters) -> Bracket {
  validate_parameters(p)
  let s = @sketch.Sketch::new()
  // Deliberately approximate seeds, not coordinates computed from dimensions.
  // Corner order: bottom-left, bottom-right, top-right, top-left.
  let corners = [
    s.add_point(0.0, 0.0),
    s.add_point(118.0, 1.0),
    s.add_point(121.0, 79.0),
    s.add_point(-1.0, 81.0),
  ]
  let bottom = s.add_line(corners[0], corners[1])
  let right = s.add_line(corners[1], corners[2])
  let top = s.add_line(corners[2], corners[3])
  // Downward left edge: its positive signed distance points into the plate.
  let left = s.add_line(corners[3], corners[0])
  s.constrain(Fix(corners[0], 0.0, 0.0)) |> ignore
  s.constrain(Horizontal(bottom)) |> ignore
  s.constrain(Vertical(right)) |> ignore
  s.constrain(Horizontal(top)) |> ignore
  s.constrain(Vertical(left)) |> ignore
  let width = s.constrain(DistanceX(corners[0], corners[1], p.width))
  let height = s.constrain(DistanceY(corners[0], corners[3], p.height))
  let axis_points = [
    s.add_point(60.0, 0.0),
    s.add_point(60.0, 80.0),
    s.add_point(0.0, 40.0),
    s.add_point(120.0, 40.0),
  ]
  s.constrain(Midpoint(axis_points[0], bottom)) |> ignore
  s.constrain(Midpoint(axis_points[1], top)) |> ignore
  s.constrain(Midpoint(axis_points[2], left)) |> ignore
  s.constrain(Midpoint(axis_points[3], right)) |> ignore
  let vertical_axis = s.add_line(axis_points[0], axis_points[1])
  let horizontal_axis = s.add_line(axis_points[2], axis_points[3])
  // Hole order: bottom-left, bottom-right, top-left, top-right.
  let centers = [
    s.add_point(18.0, 16.0),
    s.add_point(103.0, 14.0),
    s.add_point(19.0, 63.0),
    s.add_point(101.0, 64.0),
  ]
  let horizontal_margin = s.constrain(
    DistanceToLine(centers[0], left, p.horizontal_margin),
  )
  let vertical_margin = s.constrain(
    DistanceToLine(centers[0], bottom, p.vertical_margin),
  )
  s.constrain(Mirror(centers[0], centers[1], vertical_axis)) |> ignore
  s.constrain(Mirror(centers[0], centers[2], horizontal_axis)) |> ignore
  s.constrain(Mirror(centers[1], centers[3], horizontal_axis)) |> ignore
  let holes = centers.map(center => s.add_circle(center, 4.5))
  let radius = s.constrain(Radius(holes[0], p.hole_radius))
  for i = 1; i < holes.length(); i = i + 1 {
    s.constrain(EqualRadius(holes[0], holes[i])) |> ignore
  }
  let conflict = s.constrain(DistanceX(corners[0], corners[1], p.width + 10.0))
  s.set_constraint_enabled(conflict, false) |> ignore
  {
    sketch: s,
    corners,
    axis_points,
    centers,
    holes,
    width,
    height,
    radius,
    horizontal_margin,
    vertical_margin,
    conflict,
  }
}

///|
/// Editing only replaces driving relations; it never assigns solved coordinates.
fn Bracket::edit(self : Bracket, p : Parameters) -> Unit {
  validate_parameters(p)
  let s = self.sketch
  require_true(
    s.set_constraint(
      self.width,
      DistanceX(self.corners[0], self.corners[1], p.width),
    ) &&
    s.set_constraint(
      self.height,
      DistanceY(self.corners[0], self.corners[3], p.height),
    ) &&
    s.set_constraint(self.radius, Radius(self.holes[0], p.hole_radius)),
    "Missing driving dimension",
  )
  // Find the stored left and bottom lines through the existing relations.
  let left = match s.constraint(self.horizontal_margin) {
    Some(DistanceToLine(_, line, _)) => line
    _ => abort("Missing horizontal margin relation")
  }
  let bottom = match s.constraint(self.vertical_margin) {
    Some(DistanceToLine(_, line, _)) => line
    _ => abort("Missing vertical margin relation")
  }
  require_true(
    s.set_constraint(
      self.horizontal_margin,
      DistanceToLine(self.centers[0], left, p.horizontal_margin),
    ) &&
    s.set_constraint(
      self.vertical_margin,
      DistanceToLine(self.centers[0], bottom, p.vertical_margin),
    ),
    "Missing margin dimension",
  )
}

///|
/// Independent closed-form oracle, used only to verify the solver's result.
fn Bracket::verify(self : Bracket, p : Parameters) -> Unit {
  let expected_corners = [
    (0.0, 0.0),
    (p.width, 0.0),
    (p.width, p.height),
    (0.0, p.height),
  ]
  let expected_axes = [
    (p.width / 2.0, 0.0),
    (p.width / 2.0, p.height),
    (0.0, p.height / 2.0),
    (p.width, p.height / 2.0),
  ]
  let expected_centers = [
    (p.horizontal_margin, p.vertical_margin),
    (p.width - p.horizontal_margin, p.vertical_margin),
    (p.horizontal_margin, p.height - p.vertical_margin),
    (p.width - p.horizontal_margin, p.height - p.vertical_margin),
  ]
  for i, id in self.corners {
    let point = self.sketch.point(id).unwrap()
    near(point.x, expected_corners[i].0)
    near(point.y, expected_corners[i].1)
  }
  for i, id in self.axis_points {
    let point = self.sketch.point(id).unwrap()
    near(point.x, expected_axes[i].0)
    near(point.y, expected_axes[i].1)
  }
  for i, id in self.centers {
    let point = self.sketch.point(id).unwrap()
    near(point.x, expected_centers[i].0)
    near(point.y, expected_centers[i].1)
    near(self.sketch.radius(self.holes[i]).unwrap(), p.hole_radius)
  }
}

///|
fn Bracket::solve_checked(self : Bracket, p : Parameters) -> @sketch.Solution {
  let solution = match self.sketch.solve_and_apply() {
    Ok(solution) => solution
    Err(error) => abort(error.message())
  }
  require_true(
    solution.report.is_satisfied() &&
    solution.report.local_dof == 0 &&
    solution.report.variables == 28 &&
    solution.report.equations == 28 &&
    solution.report.dependent_equations == 0,
    "Bracket must be satisfied and locally fully constrained",
  )
  self.verify(p)
  solution
}

///|
fn Bracket::geometry_values(self : Bracket) -> Array[Double] {
  let values = []
  for ids in [self.corners, self.axis_points, self.centers] {
    for id in ids {
      let point = self.sketch.point(id).unwrap()
      values.push(point.x)
      values.push(point.y)
    }
  }
  for id in self.holes {
    values.push(self.sketch.radius(id).unwrap())
  }
  values
}

///|
fn Bracket::reject_conflict(self : Bracket, p : Parameters) -> @sketch.Solution {
  let saved = self.geometry_values()
  require_true(
    self.sketch.set_constraint(
      self.conflict,
      DistanceX(self.corners[0], self.corners[1], p.width + 10.0),
    ) &&
    self.sketch.set_constraint_enabled(self.conflict, true),
    "Missing conflict relation",
  )
  let failed = match self.sketch.solve_and_apply() {
    Ok(solution) => solution
    Err(error) => abort(error.message())
  }
  require_true(
    !failed.report.is_satisfied() && failed.report.unsatisfied().length() > 0,
    "Contradictory width must not be applied",
  )
  let retained = self.geometry_values()
  for i, value in saved {
    require_true(value == retained[i], "Failed solve changed bracket geometry")
  }
  for finding in failed.report.unsatisfied() {
    require_true(
      self.sketch.constraint(finding.id) is Some(_),
      "Diagnostic no longer maps to a relation",
    )
  }
  failed
}

///|
fn points_json(s : @sketch.Sketch, ids : Array[@sketch.PointId]) -> String {
  let mut text = "["
  for i, id in ids {
    if i > 0 {
      text = text + ","
    }
    let point = s.point(id).unwrap()
    text = text + "[\{point.x},\{point.y}]"
  }
  text + "]"
}

///|
fn Bracket::emit(
  self : Bracket,
  stage : String,
  p : Parameters,
  solution : @sketch.Solution,
) -> Unit {
  let s = self.sketch
  let report = solution.report
  let status = match report.status {
    Satisfied => "Satisfied"
    Stalled => "Stalled"
    IterationLimit => "IterationLimit"
  }
  let mut holes = "["
  for i, id in self.holes {
    if i > 0 {
      holes = holes + ","
    }
    let point = s.point(self.centers[i]).unwrap()
    let radius = s.radius(id).unwrap()
    holes = holes + "[\{point.x},\{point.y},\{radius}]"
  }
  holes = holes + "]"
  let mut residuals = "["
  for i, residual in report.residuals {
    if i > 0 {
      residuals = residuals + ","
    }
    residuals = residuals +
      "{\"id\":\{residual.id.index()},\"active\":\{residual.active},\"length_error\":\{residual.length_error},\"angular_error\":\{residual.angular_error},\"tolerance_ratio\":\{residual.tolerance_ratio}}"
  }
  residuals = residuals + "]"
  let corners = points_json(s, self.corners)
  let axes = points_json(s, self.axis_points)
  println(
    "{\"stage\":\"\{stage}\",\"parameters\":{\"width\":\{p.width},\"height\":\{p.height},\"hole_radius\":\{p.hole_radius},\"horizontal_margin\":\{p.horizontal_margin},\"vertical_margin\":\{p.vertical_margin}},\"constraint_ids\":{\"width\":\{self.width.index()},\"height\":\{self.height.index()},\"radius\":\{self.radius.index()},\"horizontal_margin\":\{self.horizontal_margin.index()},\"vertical_margin\":\{self.vertical_margin.index()},\"conflict\":\{self.conflict.index()}},\"geometry\":{\"corners\":\{corners},\"axis_points\":\{axes},\"holes\":\{holes}},\"report\":{\"status\":\"\{status}\",\"local_dof\":\{report.local_dof},\"variables\":\{report.variables},\"equations\":\{report.equations},\"iterations\":\{report.iterations},\"max_tolerance_ratio\":\{report.max_tolerance_ratio},\"residuals\":\{residuals}},\"applied\":\{report.is_satisfied()}}",
  )
}

///|
/// JSON Lines are read by scripts/bracket_showcase.cjs for independent checking
/// and SVG generation. A failed assertion aborts with a nonzero exit status.
fn main {
  let initial : Parameters = {
    width: 120.0,
    height: 80.0,
    hole_radius: 5.0,
    horizontal_margin: 20.0,
    vertical_margin: 15.0,
  }
  let bracket = new_bracket(initial)
  bracket.emit("initial", initial, bracket.solve_checked(initial))
  let widened : Parameters = { ..initial, width: 160.0, }
  bracket.edit(widened)
  bracket.emit("widened", widened, bracket.solve_checked(widened))
  let larger_holes : Parameters = { ..widened, hole_radius: 8.0, }
  bracket.edit(larger_holes)
  bracket.emit(
    "larger_holes",
    larger_holes,
    bracket.solve_checked(larger_holes),
  )
  let edited : Parameters = { ..larger_holes, horizontal_margin: 30.0, }
  bracket.edit(edited)
  bracket.emit("edited", edited, bracket.solve_checked(edited))
  bracket.emit("conflict", edited, bracket.reject_conflict(edited))
  require_true(
    bracket.sketch.set_constraint_enabled(bracket.conflict, false),
    "Cannot disable conflict",
  )
  bracket.emit("recovered", edited, bracket.solve_checked(edited))
}
