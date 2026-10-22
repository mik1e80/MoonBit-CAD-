///|
priv struct Measurement {
  case_name : String
  point_count : Int32
  constraint_count : Int32
  seed : Int32
  repetition : Int32
  elapsed_us : Double
  status : String
  error : String
  iterations : Int32
  variables : Int32
  equations : Int32
  local_dof : Int32
  dependent_equations : Int32
  max_tolerance_ratio : Double
  max_length_error : Double
  residual_ratios : Array[Double]
  warmup_statuses : Array[String]
  initial_points : Array[Array[Double]]
  points : Array[Array[Double]]
  retained_points : Array[Array[Double]]
} derive(ToJson)

///|
fn random(state : Array[Int32]) -> Double {
  let value = 16807 * (state[0] % 127773) - 2836 * (state[0] / 127773)
  state[0] = if value > 0 { value } else { value + 2147483647 }
  state[0].to_double() / 2147483647.0
}

///|
fn target(i : Int32) -> @sketch.Point {
  { x: i.to_double(), y: if i % 2 == 0 { 0.0 } else { 2.0 }, }
}

///|
fn length(a : @sketch.Point, b : @sketch.Point) -> Double {
  @math.hypot(b.x - a.x, b.y - a.y)
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
fn run_case(
  name : String,
  count : Int32,
  warmups : Int32,
  repetitions : Int32,
) -> Unit {
  let s = @sketch.Sketch::new()
  let seed = 20261022 + count * 31
  let state = [seed]
  for i = 0; i < 5; i = i + 1 {
    random(state) |> ignore
  }
  let targets = Array::makei(count, i => target(i))
  let ids = targets.map(p => {
    s.add_point(
      p.x + 0.05 * (2.0 * random(state) - 1.0),
      p.y + 0.05 * (2.0 * random(state) - 1.0),
    )
  })
  // Two positioned vertices, all adjacent edges, all two-hop diagonals and
  // one closing edge: exactly 2*count distinct relations, not duplicate fixes.
  s.constrain(Fix(ids[0], targets[0].x, targets[0].y)) |> ignore
  s.constrain(Fix(ids[1], targets[1].x, targets[1].y)) |> ignore
  for i = 1; i < count; i = i + 1 {
    s.constrain(
      Distance(ids[i - 1], ids[i], length(targets[i - 1], targets[i])),
    )
    |> ignore
  }
  for i = 2; i < count; i = i + 1 {
    s.constrain(
      Distance(ids[i - 2], ids[i], length(targets[i - 2], targets[i])),
    )
    |> ignore
  }
  s.constrain(
    Distance(ids[0], ids[count - 1], length(targets[0], targets[count - 1])),
  )
  |> ignore
  let initial_points = stored(s, ids)
  // solve() never applies a solution. Every warmup/repetition therefore starts
  // from the same immutable initial geometry, not an already-solved sketch.
  let warmup_statuses = []
  for i = 0; i < warmups; i = i + 1 {
    let status = match s.solve() {
      Err(_) => "Error"
      Ok(solution) =>
        match solution.report.status {
          Satisfied => "Satisfied"
          Stalled => "Stalled"
          IterationLimit => "IterationLimit"
        }
    }
    warmup_statuses.push(status)
  }
  for repetition = 0; repetition < repetitions; repetition = repetition + 1 {
    let start = @clock.monotonic_clock_start()
    let result = s.solve()
    let elapsed_us = @clock.monotonic_clock_end(start)
    let row : Measurement = {
      case_name: name,
      point_count: count,
      constraint_count: count * 2,
      seed,
      repetition,
      elapsed_us,
      status: "Error",
      error: "",
      iterations: 0,
      variables: 0,
      equations: 0,
      local_dof: 0,
      dependent_equations: 0,
      max_tolerance_ratio: 0.0,
      max_length_error: 0.0,
      residual_ratios: [],
      warmup_statuses,
      initial_points,
      points: [],
      retained_points: stored(s, ids),
    }
    let row = match result {
      Err(error) => { ..row, error, }
      Ok(solution) => {
        let report = solution.report
        let mut max_length_error = 0.0
        for r in report.residuals {
          if r.length_error > max_length_error {
            max_length_error = r.length_error
          }
        }
        {
          ..row,
          status: match report.status {
            Satisfied => "Satisfied"
            Stalled => "Stalled"
            IterationLimit => "IterationLimit"
          },
          iterations: report.iterations,
          variables: report.variables,
          equations: report.equations,
          local_dof: report.local_dof,
          dependent_equations: report.dependent_equations,
          max_tolerance_ratio: report.max_tolerance_ratio,
          max_length_error,
          residual_ratios: report.residuals.map(r => r.tolerance_ratio),
          points: ids.map(id => {
            let p = solution.point(id).unwrap()
            [p.x, p.y]
          }),
        }
      }
    }
    println(@json.to_json(row).stringify())
  }
}

///|
fn main {
  let smoke = @env.get_env_var("CAD_SKETCH_BENCH_SMOKE") is Some("1")
  let warmups = if smoke { 0 } else { 1 }
  let repetitions = if smoke { 1 } else { 3 }
  let metadata : Json = {
    "kind": "cad_sketch_benchmark",
    "schema": 1,
    "smoke": smoke,
    "warmups": warmups,
    "repetitions": repetitions,
    "length_tolerance": 1.0e-7,
  }
  println(metadata.stringify())
  run_case("Small", 10, warmups, repetitions)
  if !smoke {
    run_case("Medium", 30, warmups, repetitions)
    run_case("Large", 60, warmups, repetitions)
    run_case("Stress", 100, warmups, repetitions)
  }
}
