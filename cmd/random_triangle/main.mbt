///|
priv struct Sample {
  index : Int32
  seed : Int32
  initial_points : Array[Array[Double]]
  points : Array[Array[Double]]
  stored_points : Array[Array[Double]]
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
// Independent per-case Park-Miller/Schrage seed, with no retry or rejection.
fn random(state : Array[Int32]) -> Double {
  let value = 16807 * (state[0] % 127773) - 2836 * (state[0] / 127773)
  state[0] = if value > 0 { value } else { value + 2147483647 }
  state[0].to_double() / 2147483647.0
}

///|
fn stored(
  s : @sketch.Sketch,
  ids : Array[@sketch.PointId],
) -> Array[Array[Double]] {
  ids.map(id => {
    let p = s.point(id).unwrap()
    [p.x, p.y]
  })
}

///|
fn sample(index : Int32) -> Sample {
  let seed = 20261022 + index * 97
  let state = [seed]
  for i = 0; i < 5; i = i + 1 {
    random(state) |> ignore
  }
  let s = @sketch.Sketch::new()
  // All six coordinates are sampled in (-10,10), not near a known solution.
  let ids = Array::makei(3, _ => {
    s.add_point(20.0 * random(state) - 10.0, 20.0 * random(state) - 10.0)
  })
  let initial_points = stored(s, ids)
  s.constrain(Distance(ids[0], ids[1], 3.0)) |> ignore
  s.constrain(Distance(ids[1], ids[2], 4.0)) |> ignore
  s.constrain(Distance(ids[0], ids[2], 5.0)) |> ignore
  // No anchors, direction constraints, exact-coordinate resets or restarts.
  // Translation, rotation and reflection are all valid for this experiment.
  let row : Sample = {
    index,
    seed,
    initial_points,
    points: [],
    stored_points: [],
    status: "Invalid",
    error: "",
    iterations: 0,
    variables: 0,
    equations: 0,
    local_dof: 0,
    max_tolerance_ratio: 0.0,
    residual_ratios: [],
  }
  match s.solve_and_apply() {
    Err(error) => { ..row, error, stored_points: stored(s, ids), }
    Ok(solution) => {
      let report = solution.report
      {
        ..row,
        points: ids.map(id => {
          let p = solution.point(id).unwrap()
          [p.x, p.y]
        }),
        stored_points: stored(s, ids),
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
        residual_ratios: report.residuals.map(r => r.tolerance_ratio),
      }
    }
  }
}

///|
fn main {
  println(
    "{\"kind\":\"random_triangle\",\"schema\":1,\"cases\":1000,\"seed\":20261022,\"seed_step\":97,\"warmup\":5,\"coordinate_range\":[-10,10],\"sides\":[3,4,5],\"length_tolerance\":1e-7,\"max_iterations\":200}",
  )
  for index = 0; index < 1000; index = index + 1 {
    println(@json.to_json(sample(index)).stringify())
  }
}
