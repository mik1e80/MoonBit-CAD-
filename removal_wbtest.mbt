///|
test "remove an active conflict permanently without changing stored geometry" {
  let s = Sketch::new()
  let p = s.add_point(2.0, 3.0)
  let fixed = s.constrain(Fix(p, 2.0, 3.0))
  let conflict = s.constrain(Fix(p, 12.0, 3.0))
  assert_false(s.solve().unwrap().report.is_satisfied())
  let before = s.point(p).unwrap()
  assert_true(s.remove_constraint(conflict))
  let retained = s.point(p).unwrap()
  assert_eq(retained.x, before.x)
  assert_eq(retained.y, before.y)
  assert_true(s.constraint(conflict) is None)
  assert_true(s.constraint_enabled(conflict) is None)
  assert_false(s.remove_constraint(conflict))
  assert_false(s.set_constraint_enabled(conflict, true))
  assert_false(s.set_constraint(conflict, Fix(p, 2.0, 3.0)))
  let result = s.solve_and_apply().unwrap()
  assert_true(result.report.is_satisfied())
  assert_eq(result.report.equations, 2)
  assert_eq(result.report.local_dof, 0)
  assert_eq(result.report.residuals.length(), 1)
  assert_true(result.report.residual(conflict) is None)
  assert_true(result.report.residual(fixed).unwrap().active)
}

///|
test "remove middle first and last relations while preserving disabled neighbors" {
  let s = Sketch::new()
  let p = s.add_point(1.0, 2.0)
  let first = s.constrain(Fix(p, 1.0, 2.0))
  let middle = s.constrain(Fix(p, 1.0, 2.0))
  let disabled = s.constrain(Fix(p, 500.0, 500.0))
  let last = s.constrain(Fix(p, 1.0, 2.0))
  assert_true(s.set_constraint_enabled(disabled, false))
  assert_true(s.remove_constraint(middle))
  let report = solved(s).report
  assert_eq(report.residuals.length(), 3)
  assert_eq(report.equations, 4)
  assert_true(report.residual(middle) is None)
  assert_false(report.residual(disabled).unwrap().active)
  assert_true(s.remove_constraint(first))
  assert_true(s.constraint_enabled(disabled) is Some(false))
  assert_true(s.constraint_enabled(last) is Some(true))
  assert_true(s.set_constraint(last, Fix(p, 9.0, 2.0)))
  assert_true(s.solve_and_apply().unwrap().report.is_satisfied())
  near(s.point(p).unwrap().x, 9.0)
  assert_true(s.remove_constraint(last))
  let report = solved(s).report
  assert_eq(report.equations, 0)
  assert_eq(report.local_dof, 2)
  assert_eq(report.residuals.length(), 1)
  assert_eq(report.residuals[0].id.index(), disabled.index())
  assert_false(report.residual(disabled).unwrap().active)
  assert_true(s.remove_constraint(disabled))
  let report = solved(s).report
  assert_eq(report.residuals.length(), 0)
  assert_eq(report.variables, 2)
  assert_eq(report.local_dof, 2)
}

///|
test "reports preserve historical IDs while new reports use only live relations" {
  let s = Sketch::new()
  let p = s.add_point(0.0, 0.0)
  let removed = s.constrain(Fix(p, 0.0, 0.0))
  let survivor = s.constrain(Fix(p, 10.0, 0.0))
  let disabled = s.constrain(Fix(p, 20.0, 0.0))
  s.set_constraint_enabled(disabled, false) |> ignore
  let old = s.solve().unwrap().report
  assert_false(old.is_satisfied())
  assert_true(s.remove_constraint(removed))
  assert_true(s.remove_constraint(disabled))
  let added = s.constrain(Fix(p, 20.0, 0.0))
  assert_true(added.index() > disabled.index())
  let current = s.solve().unwrap().report
  assert_false(current.is_satisfied())
  assert_eq(current.residuals.length(), 2)
  assert_true(current.residual(removed) is None)
  assert_true(current.residual(disabled) is None)
  assert_eq(current.residuals[0].id.index(), survivor.index())
  assert_eq(current.residuals[1].id.index(), added.index())
  for finding in current.unsatisfied() {
    assert_true(s.constraint(finding.id) is Some(_))
    assert_true(current.residual(finding.id).unwrap().tolerance_ratio > 1.0)
  }
  assert_eq(old.residuals.length(), 3)
  assert_true(old.residual(removed).unwrap().active)
  assert_false(old.residual(disabled).unwrap().active)
  assert_true(old.residual(added) is None)
  assert_true(s.constraint(removed) is None)
  assert_true(s.set_constraint(added, Fix(p, 10.0, 0.0)))
  assert_true(s.solve_and_apply().unwrap().report.is_satisfied())
  near(s.point(p).unwrap().x, 10.0)
}

///|
test "foreign negative and unknown handles cannot remove a live relation" {
  let a = Sketch::new()
  let ap = a.add_point(0.0, 0.0)
  let foreign = a.constrain(Fix(ap, 0.0, 0.0))
  let b = Sketch::new()
  let bp = b.add_point(0.0, 0.0)
  let own = b.constrain(Fix(bp, 0.0, 0.0))
  assert_eq(foreign.index(), own.index())
  assert_false(b.remove_constraint(foreign))
  assert_false(b.remove_constraint(b.constraint_id(-1)))
  assert_false(b.remove_constraint(b.constraint_id(99)))
  assert_true(b.constraint(own) is Some(Fix(_, _, _)))
  assert_true(b.constraint_enabled(own) is Some(true))
  let report = solved(b).report
  assert_eq(report.residuals.length(), 1)
  assert_true(report.residual(foreign) is None)
}

///|
test "removing a driving dimension changes DOF and readding creates a fresh handle" {
  let s = Sketch::new()
  let origin = s.add_point(0.0, 0.0)
  let p = s.add_point(3.0, 4.0)
  s.constrain(Fix(origin, 0.0, 0.0)) |> ignore
  let x = s.constrain(DistanceX(origin, p, 3.0))
  let y = s.constrain(DistanceY(origin, p, 4.0))
  assert_eq(solved(s).report.local_dof, 0)
  assert_true(s.remove_constraint(x))
  let report = solved(s).report
  assert_eq(report.local_dof, 1)
  assert_eq(report.equations, 3)
  assert_true(report.residual(x) is None)
  assert_true(report.residual(y).unwrap().active)
  let fresh = s.constrain(DistanceX(origin, p, 7.0))
  assert_true(fresh.index() > y.index())
  let solved = s.solve_and_apply().unwrap()
  assert_true(solved.report.is_satisfied())
  assert_eq(solved.report.local_dof, 0)
  near(s.point(p).unwrap().x, 7.0)
  assert_false(s.set_constraint_enabled(x, true))
}

///|
test "deleted invalid dimensions and references leave no validation or scale effect" {
  let s = Sketch::new()
  let p = s.add_point(0.0, 0.0)
  let other = Sketch::new()
  let foreign = other.add_point(0.0, 0.0)
  let invalid = s.constrain(Fix(foreign, 0.0, 0.0))
  assert_true(s.solve() is Err(_))
  assert_true(s.remove_constraint(invalid))
  let giant = s.constrain(Fix(p, 1.0e100, 1.0e100))
  assert_true(s.solve() is Err(_))
  assert_true(s.remove_constraint(giant))
  let nan = s.constrain(Fix(p, 0.0 / 0.0, 0.0))
  assert_true(s.set_constraint_enabled(nan, false))
  assert_true(s.remove_constraint(nan))
  let report = solved(s).report
  assert_eq(report.residuals.length(), 0)
  assert_eq(report.equations, 0)
  assert_eq(report.local_dof, 2)
}

///|
test "deletion frees the live constraint limit while disabled relations still count" {
  let s = Sketch::new()
  let p = s.add_point(0.0, 0.0)
  let ids = []
  for i = 0; i < 512; i = i + 1 {
    let id = s.constrain(Fix(p, 0.0, 0.0))
    s.set_constraint_enabled(id, false) |> ignore
    ids.push(id)
  }
  let report = solved(s).report
  assert_eq(report.residuals.length(), 512)
  assert_eq(report.equations, 0)
  let extra = s.constrain(Fix(p, 0.0, 0.0))
  assert_true(s.solve() is Err(_))
  assert_true(s.remove_constraint(ids[200]))
  let report = solved(s).report
  assert_eq(report.residuals.length(), 512)
  assert_eq(report.equations, 2)
  assert_eq(report.local_dof, 0)
  assert_true(report.residual(ids[200]) is None)
  assert_false(report.residual(ids[511]).unwrap().active)
  assert_true(report.residual(extra).unwrap().active)
  let over = s.constrain(Fix(p, 0.0, 0.0))
  assert_true(s.solve() is Err(_))
  assert_true(s.remove_constraint(extra))
  assert_true(solved(s).report.residual(over).unwrap().active)
}

///|
test "many add remove cycles do not revive stale handles or consume the live limit" {
  let s = Sketch::new()
  let p = s.add_point(0.0, 0.0)
  let anchor = s.constrain(Fix(p, 0.0, 0.0))
  let retired = s.constrain(Fix(p, 0.0, 0.0))
  assert_true(s.remove_constraint(retired))
  for i = 0; i < 1024; i = i + 1 {
    let temporary = s.constrain(Fix(p, 0.0, 0.0))
    assert_true(s.remove_constraint(temporary))
  }
  let fresh = s.constrain(Fix(p, 0.0, 0.0))
  assert_true(fresh.index() > 1024)
  assert_false(s.remove_constraint(retired))
  assert_false(s.set_constraint(retired, Fix(p, 99.0, 99.0)))
  let report = solved(s).report
  assert_eq(report.residuals.length(), 2)
  assert_true(report.residual(anchor).unwrap().active)
  assert_true(report.residual(fresh).unwrap().active)
  assert_true(report.residual(retired) is None)
}

///|
test "validation and evaluation errors keep stable IDs after compaction" {
  let s = Sketch::new()
  let p = s.add_point(0.0, 0.0)
  let removed = s.constrain(Fix(p, 0.0, 0.0))
  let bad = s.constrain(Fix(p, 0.0 / 0.0, 0.0))
  assert_true(s.remove_constraint(removed))
  assert_true(solve_error(s) is InvalidConstraint(id) && id.index == bad.index)
  let inner = s.add_circle(p, 1.0)
  let outer = s.add_circle(p, 2.0)
  assert_true(s.set_constraint(bad, InternalTangent(inner, outer)))
  assert_true(solve_error(s) is InvalidConstraint(id) && id.index == bad.index)
  assert_true(s.remove_constraint(bad))
  assert_eq(solved(s).report.residuals.length(), 0)
}

///|
test "large stable identifiers do not require sparse residual storage" {
  let s = Sketch::new()
  let p = s.add_point(0.0, 0.0)
  // Simulate a long-lived sketch without allocating billions of relations.
  s.next_constraint[0] = 2147483646
  let id = s.constrain(Fix(p, 0.0, 0.0))
  assert_eq(id.index(), 2147483646)
  let report = solved(s).report
  assert_eq(report.residuals.length(), 1)
  assert_true(report.residual(id).unwrap().active)
  assert_true(s.remove_constraint(id))
  assert_true(s.constraint(id) is None)
  assert_eq(solved(s).report.residuals.length(), 0)
  assert_true(report.residual(id).unwrap().active)
}
