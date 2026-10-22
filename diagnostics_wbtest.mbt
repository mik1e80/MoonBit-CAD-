///|
test "likely conflicts rank weighted errors and break ties by stable ID" {
  let s = Sketch::new()
  let p = s.add_point(0.0, 0.0)
  let ids = Array::makei(4, _ => s.constrain(Fix(p, 0.0, 0.0)))
  let base = solved(s).report
  // Input order is deliberately different from ID order. Length and angular
  // errors have different units; only the already-weighted ratio is comparable.
  let report = {
    ..base,
    residuals: [
      {
        id: ids[2],
        active: true,
        length_error: 100.0,
        angular_error: 0.0,
        tolerance_ratio: 2.0,
      },
      {
        id: ids[3],
        active: true,
        length_error: 0.0,
        angular_error: 0.01,
        tolerance_ratio: 10.0,
      },
      {
        id: ids[1],
        active: true,
        length_error: 0.0,
        angular_error: 0.01,
        tolerance_ratio: 10.0,
      },
      {
        id: ids[0],
        active: true,
        length_error: 1.0,
        angular_error: 0.0,
        tolerance_ratio: 5.0,
      },
    ],
  }
  let findings = report.likely_conflicts()
  assert_eq(findings.map(r => r.id.index()), [1, 3, 0, 2])
  assert_eq(report.unsatisfied().map(r => r.id.index()), [2, 3, 1, 0])
  assert_eq(report.residuals.map(r => r.id.index()), [2, 3, 1, 0])
  // Returned arrays are caller-owned, so even mutation must not reorder reports.
  findings.clear()
  assert_eq(report.likely_conflicts().map(r => r.id.index()), [1, 3, 0, 2])
  assert_eq(report.residual(ids[3]).unwrap().tolerance_ratio, 10.0)
}

///|
test "likely conflicts exclude disabled satisfied and exactly-at-tolerance rows" {
  let s = Sketch::new()
  let p = s.add_point(0.0, 0.0)
  let ids = Array::makei(5, _ => s.constrain(Fix(p, 0.0, 0.0)))
  let base = solved(s).report
  let ratios = [0.0, 0.99, 1.0, 1.0000001, 1000.0]
  let report = {
    ..base,
    residuals: Array::makei(5, i => {
      id: ids[i],
      active: i != 4,
      length_error: ratios[i],
      angular_error: 0.0,
      tolerance_ratio: ratios[i],
    }),
  }
  let findings = report.likely_conflicts()
  assert_eq(findings.length(), 1)
  assert_eq(findings[0].id.index(), ids[3].index())
  assert_eq(findings[0].length_error, ratios[3])
  assert_eq(findings[0].tolerance_ratio, ratios[3])
}

///|
test "satisfied redundant and unconstrained reports have no likely conflicts" {
  assert_eq(solved(Sketch::new()).report.likely_conflicts().length(), 0)
  let s = Sketch::new()
  let p = s.add_point(1.0, 2.0)
  let free = solved(s).report
  assert_eq(free.local_dof, 2)
  assert_eq(free.likely_conflicts().length(), 0)
  s.constrain(Fix(p, 1.0, 2.0)) |> ignore
  s.constrain(Fix(p, 1.0, 2.0)) |> ignore
  let report = solved(s).report
  assert_eq(report.dependent_equations, 2)
  assert_eq(report.likely_conflicts().length(), 0)
}

///|
test "actual conflicting fixes rank diagnostics without applying candidate geometry" {
  let s = Sketch::new()
  let p = s.add_point(0.0, 0.0)
  let q = s.add_point(100.0, 5.0)
  let first = s.constrain(Fix(p, 0.0, 0.0))
  let middle = s.constrain(Fix(p, 6.0, 0.0))
  let last = s.constrain(Fix(p, 30.0, 0.0))
  let unrelated = s.constrain(Fix(q, 100.0, 5.0))
  let disabled = s.constrain(Fix(p, 999.0, 0.0))
  s.set_constraint_enabled(disabled, false) |> ignore
  let report = s.solve_and_apply().unwrap().report
  assert_false(report.is_satisfied())
  let findings = report.likely_conflicts()
  assert_eq(findings.map(r => r.id.index()), [
    last.index(),
    first.index(),
    middle.index(),
  ])
  assert_eq(findings.length(), report.unsatisfied().length())
  assert_eq(report.residuals[0].id.index(), first.index())
  for finding in findings {
    assert_true(s.constraint(finding.id) is Some(Fix(_, _, _)))
    assert_eq(
      report.residual(finding.id).unwrap().tolerance_ratio,
      finding.tolerance_ratio,
    )
  }
  assert_true(report.residual(unrelated).unwrap().tolerance_ratio <= 1.0)
  assert_false(report.residual(disabled).unwrap().active)
  assert_eq(s.point(p).unwrap().x, 0.0)
  assert_eq(s.point(q).unwrap().x, 100.0)
  assert_true(s.remove_constraint(last))
  assert_true(s.remove_constraint(middle))
  let recovered = s.solve_and_apply().unwrap().report
  assert_true(recovered.is_satisfied())
  assert_eq(recovered.likely_conflicts().length(), 0)
  assert_eq(report.likely_conflicts()[0].id.index(), last.index())
  assert_true(s.constraint(last) is None)
}

///|
test "singular but satisfiable distance can produce likely conflict symptoms" {
  let s = Sketch::new()
  let a = s.add_point(0.0, 0.0)
  let b = s.add_point(0.0, 0.0)
  s.constrain(Fix(a, 0.0, 0.0)) |> ignore
  let dimension = s.constrain(Distance(a, b, 5.0))
  let stalled = s.solve().unwrap().report
  assert_false(stalled.is_satisfied())
  assert_eq(stalled.likely_conflicts().length(), 1)
  assert_eq(stalled.likely_conflicts()[0].id.index(), dimension.index())
  // The same constraints are satisfiable from a nonsingular initial guess.
  assert_true(s.set_point(b, { x: 3.0, y: 0.0, }))
  assert_eq(solved(s).report.likely_conflicts().length(), 0)
}

///|
test "overflowed ratios sort deterministically before finite violations" {
  let s = Sketch::new()
  let p = s.add_point(0.0, 0.0)
  let ids = Array::makei(3, _ => s.constrain(Fix(p, 0.0, 0.0)))
  let base = solved(s).report
  let report = {
    ..base,
    residuals: Array::makei(3, i => {
      id: ids[2 - i],
      active: true,
      length_error: 1.0,
      angular_error: 0.0,
      tolerance_ratio: if i == 1 {
        2.0
      } else {
        1.0 / 0.0
      },
    }),
  }
  assert_eq(report.likely_conflicts().map(r => r.id.index()), [0, 2, 1])
}
