# MoonBit CAD Sketch

纯 MoonBit 的二维草图约束求解库。源码版本 `0.1.0` 尚未发布到 Mooncakes；安装、完整约束表、诊断语义和数值边界见 [README.md](README.md)。

需要 `moonc >= 0.10.15`；已用 `moon 0.1.20261012` 和 `moonc 0.10.15+943464bfa` 验证。

下面的公开接口示例随 `moon test` 执行：

```mbt check
///|
test "dimensioned segment and repeated solve" {
  let s = @sketch.Sketch::new()
  let a = s.add_point(0.0, 0.0)
  let b = s.add_point(3.0, 0.5)
  s.constrain(Fix(a, 0.0, 0.0)) |> ignore
  s.constrain(Horizontal(s.add_line(a, b))) |> ignore
  let dimension = s.constrain(Distance(a, b, 5.0))
  let first = s.solve_and_apply().unwrap()
  assert_true(first.report.is_satisfied())
  assert_eq(first.report.local_dof, 0)
  assert_true((s.point(b).unwrap().x - 5.0).abs() < 1.0e-6)
  assert_true(s.set_constraint(dimension, Distance(a, b, 7.0)))
  let second = s.solve_and_apply().unwrap()
  assert_true(second.report.is_satisfied())
  assert_true((second.point(b).unwrap().x - 7.0).abs() < 1.0e-6)
}
```

仅 `Satisfied` 表示返回坐标的全部残差分量满足指定容差。`Stalled` / `IterationLimit` 不构成无解证明；残差列表不构成最小冲突集，`local_dof` 是当前构型的一阶数值估计。所有实体句柄局限于创建它们的草图。

已支持 23 种关系，包含中心对称、带符号点线距离、长度比例以及指定内外圆的内切。约束可以临时关闭，编号保持稳定：

```mbt check
///|
test "disable a conflicting edit and inspect its state" {
  let s = @sketch.Sketch::new()
  let p = s.add_point(0.0, 0.0)
  s.constrain(Fix(p, 0.0, 0.0)) |> ignore
  let conflict = s.constrain(Fix(p, 10.0, 0.0))
  assert_false(s.solve().unwrap().report.is_satisfied())
  assert_true(s.set_constraint_enabled(conflict, false))
  let result = s.solve_and_apply().unwrap()
  assert_true(result.report.is_satisfied())
  assert_false(result.report.residual(conflict).unwrap().active)
  assert_true(s.constraint(conflict) is Some(Fix(_, _, _)))
}
```

完整编辑流程的可执行示例见 `cmd/edit_demo`，会验证修改尺寸、约束启停、失败回退及解析坐标。

核心库仅依赖 MoonBit core，无 C/C++ 或 JS 求解器依赖。参照 [SolveSpace 的约束建模需求](https://solvespace.com/constraints.pl)，独立实现前向自动微分、阻尼 Gauss–Newton 与增广 Givens QR。完整来源和许可说明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
