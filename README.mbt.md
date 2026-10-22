# MoonBit CAD Sketch

面向 MoonBit 应用开发者的小型二维参数化草图约束求解库。输入点、线、圆和几何关系，求解坐标与半径；修改尺寸后重新求解，并报告残差、局部自由度和求解状态。

适用于参数化零件草图、草图编辑器集成及小型平面机构教学。核心库仅依赖 MoonBit core，支持 wasm、wasm-gc、JS 和 native；当前上限为 256 个标量变量、512 条线、512 条约束。非线性求解依赖初值，局部自由度是一阶数值估计。

源码版本 `0.1.0` 尚未发布到 Mooncakes；安装、完整约束表、诊断语义和数值边界见 [README.md](README.md)，目标用户与应用范围见 [项目定位与范围](docs/POSITIONING.md)。

完整文档入口：[快速开始](docs/QUICK_START.md)、[约束参考](docs/CONSTRAINTS.md)、[求解](docs/SOLVER.md)、[诊断](docs/DIAGNOSTICS.md)和[限制](docs/LIMITATIONS.md)。

默认选项即可开始；[API 使用指南](docs/API_GUIDE.md)按几何、约束、求解、编辑和诊断介绍接口。需要 `moonc >= 0.10.15`。

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

求解的 `Err` 可直接匹配 `SketchError`；日志使用 `error.message()`。完整分类与迁移见 [API 指南](docs/API_GUIDE.md#类型化错误与迁移)。

```mbt check
///|
test "handle typed sketch errors through the public API" {
  let s = @sketch.Sketch::new()
  let a = s.add_point(0.0, 0.0)
  let line = s.add_line(a, a)
  match s.solve_and_apply() {
    Err(DegenerateLine(id)) => assert_eq(id.index, line.index)
    Err(error) => fail(error.message())
    Ok(_) => fail("Expected a degenerate line error")
  }
}
```

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

失败时可用 `likely_conflicts()` 按误差比降序排查启用且超标的约束，误差比相同时按约束编号升序排列。它是排序提示，不是无解证明或最小冲突集；完整语义见[失败诊断](docs/DIAGNOSTICS.md)。

```mbt check
///|
test "inspect likely conflicts by descending tolerance ratio" {
  let s = @sketch.Sketch::new()
  let p = s.add_point(0.0, 0.0)
  s.constrain(Fix(p, 0.0, 0.0)) |> ignore
  s.constrain(Fix(p, 6.0, 0.0)) |> ignore
  s.constrain(Fix(p, 30.0, 0.0)) |> ignore
  let report = s.solve_and_apply().unwrap().report
  assert_false(report.is_satisfied())
  let findings = report.likely_conflicts()
  assert_eq(findings.length(), 3)
  assert_true(findings[0].tolerance_ratio >= findings[1].tolerance_ratio)
  assert_true(findings[1].tolerance_ratio >= findings[2].tolerance_ratio)
  println("Likely conflicts (heuristic inspection order):")
  for finding in findings {
    let kind = match s.constraint(finding.id) {
      Some(Fix(_, _, _)) => "Fix"
      _ => "Other"
    }
    println(
      "#\{finding.id.index()} \{kind}; error ratio: \{finding.tolerance_ratio}",
    )
  }
  assert_eq(s.point(p).unwrap().x, 0.0)
  assert_eq(report.residuals[0].id.index(), 0)
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

`moon run examples/mirror_holes` 进一步演示等半径镜像孔位、平移对称轴后的尺寸联动及冲突编辑后的几何保留，并以解析坐标检查结果。

## 案例与验证

完整零件案例见 [四孔安装板 Showcase](docs/SHOWCASE.md)：运行 `moon run examples/parametric_bracket`，依次修改板宽、孔半径和孔心边距，验证实际孔位、冲突保留与恢复，并提供可再生成的前后对比图。

机构案例见 [Four-bar linkage](examples/four_bar/README.md)：运行 `moon run examples/four_bar`，仅修改角度约束，在同一草图中往返求解 25 个姿态，核对杆长、分支和局部自由度，并提供轨迹图与 JSON / CSV。

以下批量测量保留原源码指纹；类型化错误升级仅做定向检查，未重跑这些实验。

[Validation Suite](docs/VALIDATION.md) 自动生成 400 个模型配置，分为基础解析、平移、旋转、缩放、固定种子初始扰动和极端尺寸六组；在四后端独立核对残差与解析坐标，并记录逐案例结果。运行 `node scripts/validation_suite.cjs --check --target js` 复现。结果仅代表文档中定义的小型模型和初值范围。

另有 [3-4-5 三角形随机初值实验](docs/RANDOM_TRIANGLE.md)：六个坐标从 (-10,10) 生成，不固定位置与方向；JS 后端实测 1000 项 Satisfied、0 项 Stalled / IterationLimit / Invalid，全部通过独立边长检查。完整种子、初值和条件与结果一起保存。

[SciPy 开发参考对照](docs/SCIPY_REFERENCE.md)另验证 500 个同输入配置的坐标、半径和残差。Python / SciPy 工具不进入发布库，核心仍是纯 MoonBit runtime。

[Benchmark](docs/BENCHMARK.md)提供 10/30/60/100 点、20/60/120/200 条约束的 JS release 实测，保存迭代、收敛状态、独立残差及限定环境下的耗时。日常可用 `node scripts/benchmark.cjs --smoke --target js` 只检查最小模型。

需要 `moonc >= 0.10.15`；已用 `moon 0.1.20261012` 和 `moonc 0.10.15+943464bfa` 验证。

核心库仅依赖 MoonBit core，无 C/C++ 或 JS 求解器依赖。使用者通过几何关系调用，无需提供方程或导数。算法实现与高级设置见[内部实现](docs/ARCHITECTURE.md)，参考来源和许可说明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
