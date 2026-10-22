///|
priv struct Transform {
  x : Double
  y : Double
  angle : Double
  scale : Double
} derive(ToJson)

///|
priv struct Record {
  group : String
  index : Int32
  family : String
  seed : Int32
  parameters : Array[Double]
  transform : Transform
  length_tolerance : Double
  angular_tolerance : Double
  initial_points : Array[Array[Double]]
  initial_radii : Array[Double]
  points : Array[Array[Double]]
  radii : Array[Double]
  stored_points : Array[Array[Double]]
  stored_radii : Array[Double]
  status : String
  error : String
  iterations : Int32
  variables : Int32
  equations : Int32
  local_dof : Int32
  max_tolerance_ratio : Double
  residual_ratios : Array[Double]
} derive(ToJson)

///|
// Park-Miller with Schrage's method: all intermediate values fit Int32.
// No platform RNG or time-based seed; each case can be regenerated in isolation.
fn random(state : Array[Int32]) -> Double {
  let value = 16807 * (state[0] % 127773) - 2836 * (state[0] / 127773)
  state[0] = if value > 0 { value } else { value + 2147483647 }
  state[0].to_double() / 2147483647.0
}

///|
fn transform(t : Transform, x : Double, y : Double) -> @sketch.Point {
  let c = @math.cos(t.angle)
  let s = @math.sin(t.angle)
  { x: t.x + (x * c - y * s) * t.scale, y: t.y + (x * s + y * c) * t.scale, }
}

///|
fn stored_points(
  s : @sketch.Sketch,
  ids : Array[@sketch.PointId],
) -> Array[Array[Double]] {
  ids.map(id => {
    let p = s.point(id).unwrap()
    [p.x, p.y]
  })
}

///|
fn run_case(group : Int32, index : Int32) -> Record {
  let seed = 20261022 + index * 37
  let state = [seed]
  // Mix nearby per-case seeds before drawing dimensions.
  for i = 0; i < 5; i = i + 1 {
    random(state) |> ignore
  }
  let w = 6.0 + 18.0 * random(state)
  let h = 4.0 + 10.0 * random(state)
  let r = 0.7 + 1.3 * random(state)
  let fraction = 0.25 + 0.5 * random(state)
  let family = index % 4
  let names = [
    "analytic", "translation", "rotation", "scaling", "perturbation", "extreme",
  ]
  let t : Transform = {
    x: if group == 1 {
      (index - 30).to_double() * 5000.0
    } else {
      0.0
    },
    y: if group == 1 {
      (index % 11 - 5).to_double() * 7000.0
    } else {
      0.0
    },
    angle: if group == 2 {
      -@math.PI + 2.0 * @math.PI * (index.to_double() + 0.5) / 60.0
    } else {
      0.0
    },
    scale: if group == 3 {
      @math.pow(10.0, -6.0 + 12.0 * index.to_double() / 59.0)
    } else if group == 5 {
      [
        1.0e-150, 1.0e-100, 1.0e-50, 1.0e-12, 1.0e-9, 1.0e9, 1.0e12, 1.0e50, 1.0e80,
        1.0e90,
      ][index / 4 % 10]
    } else {
      1.0
    },
  }
  let template = match family {
    0 => [[0.0, 0.0], [w, 0.0], [w * fraction, h]]
    1 => [[0.0, 0.0], [w, 0.0], [w, h], [0.0, h]]
    2 => [[-w, 0.0], [w, 0.0], [w * fraction, h], [w * fraction, -h]]
    _ => [[-w, 0.0], [w, 0.0], [0.0, r]]
  }
  let noise = if group == 4 { 0.25 * r } else { 0.04 * r }
  let perturb_state = [seed + (if group == 4 { 100000 } else { 0 })]
  let s = @sketch.Sketch::new()
  let ids = template.map(p => {
    let q = transform(
      t,
      p[0] + noise * (2.0 * random(perturb_state) - 1.0),
      p[1] + noise * (2.0 * random(perturb_state) - 1.0),
    )
    s.add_point(q.x, q.y)
  })
  let target = template.map(p => transform(t, p[0], p[1]))
  for i = 0; i < 2; i = i + 1 {
    s.constrain(Fix(ids[i], target[i].x, target[i].y)) |> ignore
  }
  let circles = []
  match family {
    0 => {
      s.constrain(
        Distance(ids[0], ids[2], @math.hypot(w * fraction, h) * t.scale),
      )
      |> ignore
      s.constrain(
        Distance(ids[1], ids[2], @math.hypot(w * (1.0 - fraction), h) * t.scale),
      )
      |> ignore
    }
    1 => {
      let ab = s.add_line(ids[0], ids[1])
      let bc = s.add_line(ids[1], ids[2])
      let cd = s.add_line(ids[2], ids[3])
      let ad = s.add_line(ids[0], ids[3])
      s.constrain(Perpendicular(ab, bc)) |> ignore
      s.constrain(Distance(ids[1], ids[2], h * t.scale)) |> ignore
      s.constrain(Parallel(ab, cd)) |> ignore
      s.constrain(Distance(ids[2], ids[3], w * t.scale)) |> ignore
      s.constrain(Parallel(bc, ad)) |> ignore
    }
    2 => {
      let axis = s.add_line(ids[0], ids[1])
      let a = s.add_circle(
        ids[2],
        r * t.scale * (1.0 + 0.1 * random(perturb_state)),
      )
      let b = s.add_circle(
        ids[3],
        r * t.scale * (1.0 + 0.1 * random(perturb_state)),
      )
      circles.push(a)
      circles.push(b)
      s.constrain(Fix(ids[2], target[2].x, target[2].y)) |> ignore
      s.constrain(Mirror(ids[2], ids[3], axis)) |> ignore
      s.constrain(Radius(a, r * t.scale)) |> ignore
      s.constrain(EqualRadius(a, b)) |> ignore
    }
    _ => {
      let axis = s.add_line(ids[0], ids[1])
      let circle = s.add_circle(
        ids[2],
        r * t.scale * (1.0 + 0.1 * random(perturb_state)),
      )
      circles.push(circle)
      s.constrain(Radius(circle, r * t.scale)) |> ignore
      s.constrain(Tangent(axis, circle)) |> ignore
      s.constrain(Distance(ids[0], ids[2], @math.hypot(w, r) * t.scale))
      |> ignore
    }
  }
  let initial_points = stored_points(s, ids)
  let initial_radii = circles.map(id => s.radius(id).unwrap())
  let length_tolerance = 1.0e-7 * t.scale
  let angular_tolerance = 1.0e-8
  let record : Record = {
    group: names[group],
    index,
    family: ["triangle", "rectangle", "mirror_circles", "line_circle_tangent"][family],
    seed,
    parameters: [w, h, r, fraction],
    transform: t,
    length_tolerance,
    angular_tolerance,
    initial_points,
    initial_radii,
    points: [],
    radii: [],
    stored_points: [],
    stored_radii: [],
    status: "Error",
    error: "",
    iterations: 0,
    variables: 0,
    equations: 0,
    local_dof: 0,
    max_tolerance_ratio: 0.0,
    residual_ratios: [],
  }
  match
    s.solve_and_apply(options={
      ..@sketch.SolveOptions::default(),
      length_tolerance,
      angular_tolerance,
    }) {
    Err(error) =>
      {
        ..record,
        error: error.message(),
        stored_points: stored_points(s, ids),
        stored_radii: circles.map(id => s.radius(id).unwrap()),
      }
    Ok(result) => {
      let report = result.report
      {
        ..record,
        points: ids.map(id => {
          let p = result.point(id).unwrap()
          [p.x, p.y]
        }),
        radii: circles.map(id => result.radius(id).unwrap()),
        stored_points: stored_points(s, ids),
        stored_radii: circles.map(id => s.radius(id).unwrap()),
        status: match report.status {
          Satisfied => "Satisfied"
          Stalled => "Stalled"
          IterationLimit => "IterationLimit"
        },
        iterations: report.iterations,
        variables: report.variables,
        equations: report.equations,
        local_dof: report.local_dof,
        max_tolerance_ratio: report.max_tolerance_ratio,
        residual_ratios: report.residuals.map(row => row.tolerance_ratio),
      }
    }
  }
}

///|
fn main {
  println(
    "{\"kind\":\"validation_suite\",\"schema\":1,\"seed\":20261022,\"cases\":400}",
  )
  for group = 0; group < 6; group = group + 1 {
    let count = if group == 4 { 100 } else { 60 }
    for index = 0; index < count; index = index + 1 {
      println(@json.to_json(run_case(group, index)).stringify())
    }
  }
}
