# MoonBit CAD Sketch

面向 MoonBit 应用开发者的小型二维参数化草图约束求解库。输入点、线、圆和几何关系，求解坐标与半径；修改尺寸后重新求解，并报告残差、局部自由度和求解状态。

适用于参数化零件草图、草图编辑器集成及小型平面机构教学。核心库仅依赖 MoonBit core，支持 wasm、wasm-gc、JS 和 native；当前上限为 256 个标量变量、512 条线、512 条约束。非线性求解依赖初值，局部自由度是一阶数值估计。

源码版本 `0.1.0` 尚未发布到 Mooncakes；安装、完整约束表、诊断语义和数值边界见 [README.md](README.md)，目标用户与应用范围见 [项目定位与范围](docs/POSITIONING.md)。

完整零件案例见 [四孔安装板 Showcase](docs/SHOWCASE.md)：运行 `moon run cmd/bracket_demo`，依次修改板宽、孔半径和孔心边距，验证实际孔位、冲突保留与恢复，并提供可再生成的前后对比图。

机构案例见 [Four-bar linkage](examples/four_bar/README.md)：运行 `moon run examples/four_bar`，仅修改角度约束，在同一草图中往返求解 25 个姿态，核对杆长、分支和局部自由度，并提供轨迹图与 JSON / CSV。

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

已支持 24 种关系，包含直线轴对称、中心对称、带符号点线距离、长度比例以及指定内外圆的内切。约束可以临时关闭，编号保持稳定：

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

约束管理还支持永久删除。禁用保留关系和编号，删除则让旧句柄失效；新关系不会复用已删除的编号。完整语义见 [约束生命周期](docs/CONSTRAINT_LIFECYCLE.md)。

```mbt check
///|
test "edit disable remove and readd without reviving the old handle" {
  let s = @sketch.Sketch::new()
  let p = s.add_point(0.0, 0.0)
  s.constrain(Fix(p, 0.0, 0.0)) |> ignore
  let temporary = s.constrain(Fix(p, 10.0, 0.0))
  assert_true(s.set_constraint(temporary, Fix(p, 20.0, 0.0)))
  assert_true(s.set_constraint_enabled(temporary, false))
  let before = s.solve().unwrap().report
  assert_true(before.is_satisfied())
  assert_true(s.remove_constraint(temporary))
  assert_true(s.constraint(temporary) is None)
  assert_false(s.set_constraint_enabled(temporary, true))
  let replacement = s.constrain(Fix(p, 0.0, 0.0))
  assert_true(replacement.index() > temporary.index())
  let after = s.solve_and_apply().unwrap().report
  assert_true(after.is_satisfied())
  assert_true(after.residual(temporary) is None)
  assert_false(before.residual(temporary).unwrap().active)
  assert_true(before.residual(replacement) is None)
}
```

完整编辑流程的可执行示例见 `cmd/edit_demo`，会验证修改尺寸、约束启停、失败回退及解析坐标。

直线镜像使用 `Mirror(a, b, axis)`，不是中心对称 `Symmetric(a, b, center)`。下面的轴是无限延伸直线，反向定义端点不改变镜像关系：

```mbt check
///|
test "mirror a hole center about a vertical construction line" {
  let s = @sketch.Sketch::new()
  let bottom = s.add_point(10.0, 0.0)
  let top = s.add_point(10.0, 10.0)
  let left = s.add_point(6.0, 3.0)
  let right = s.add_point(13.0, 2.5)
  s.constrain(Fix(bottom, 10.0, 0.0)) |> ignore
  s.constrain(Fix(top, 10.0, 10.0)) |> ignore
  s.constrain(Fix(left, 6.0, 3.0)) |> ignore
  s.constrain(Mirror(left, right, s.add_line(bottom, top))) |> ignore
  let r = s.solve_and_apply().unwrap()
  assert_true(r.report.is_satisfied())
  assert_eq(r.report.local_dof, 0)
  assert_true((r.point(right).unwrap().x - 14.0).abs() < 1.0e-6)
  assert_true((r.point(right).unwrap().y - 3.0).abs() < 1.0e-6)
}
```

`moon run cmd/mirror_demo` 进一步演示等半径镜像孔位、平移对称轴后的尺寸联动及冲突编辑后的几何保留，并以解析坐标检查结果。

核心库仅依赖 MoonBit core，无 C/C++ 或 JS 求解器依赖。参照 [SolveSpace 的约束建模需求](https://solvespace.com/constraints.pl)，独立实现前向自动微分、阻尼 Gauss–Newton 与增广 Givens QR。完整来源和许可说明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
