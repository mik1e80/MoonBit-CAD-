# 求解与结果

- `Sketch::solve()` 返回 `Result[Solution, SketchError]`，保留原草图。
- `Sketch::solve_and_apply()` 只在全部约束达到容差时更新坐标与半径；失败时保留原草图。
- `Solution::point()` / `radius()` 可读取结果，也可检查未收敛时的最后一个被接受的迭代结果。句柄只属于创建它的草图。
- 句柄包含运行时归属标识。同号但来自其他草图的句柄不会匹配：查询返回 `None`、编辑返回 `false`，启用的约束或几何引用跨草图对象时求解返回错误；句柄不能作为持久化或跨进程标识。
- `set_point()` 修改下一次求解的初值；`set_constraint()` 修改已有尺寸或关系。它们返回是否找到相应句柄，数值合法性在 `solve()` 时统一验证。
- `set_radius()` 修改已有圆的初始半径，保留中心与关联约束；它不固定半径，驱动半径尺寸应使用 `Radius`。非法数值同样在求解时诊断。
- `set_constraint_enabled(id, false)` 暂停某条约束，传 `true` 恢复；编号与关系保留，`set_constraint()` 不改变启停状态。禁用关系不参与校验、尺度计算、方程和自由度计算，仍计入 512 条关系的存储上限；几何本身始终需要合法。
- `remove_constraint(id)` 永久删除一条现存约束并释放名额，成功返回 `true`；重复删除、未知或跨草图句柄返回 `false`。删除不修改当前几何，其他约束编号保持不变，新约束不复用已删除编号；旧句柄不能重新启用或修改。删除后的查询返回 `None`，新报告不包含它，旧报告仍保留历史残差。[完整生命周期与可运行示例](CONSTRAINT_LIFECYCLE.md)覆盖添加、修改、禁用、恢复和删除。

`SolveReport` 包含：

| 字段 | 含义 |
| --- | --- |
| `status` | `Satisfied`：返回几何的每个残差分量均达标；`Stalled`：无法继续降低误差或输出坐标精度不足；`IterationLimit`：达到迭代次数上限 |
| `local_dof` | 当前构型下估计的剩余自由度；为零不等于全局唯一解 |
| `dependent_equations` | 可选高级诊断：当前构型下的相关方程数，技术定义见[内部实现](ARCHITECTURE.md#自由度与失败的含义) |
| `residuals` | 求解时每条现存约束的启用状态 `active`、最大长度误差、角度 / 方向误差、误差与容差之比；禁用项误差置零，已删除项不包含在新报告中 |
| `unsatisfied()` | 误差与容差之比大于 1 的约束 |

`Err` 表示非法尺寸、失效引用、退化初值、资源上限或数值求值错误。**未收敛不证明无解，未满足约束列表也不是最小冲突集。** 重复约束可以被同时满足。奇异构型的一阶自由度可能高于实际运动自由度，例如完全共线的三角形；不要把它当成全局刚性证明。

失败排查可用 `report.likely_conflicts()`：返回与 `unsatisfied()` 相同的启用超标项，按 `tolerance_ratio` 降序排列，同误差比按稳定约束编号升序排列。它不改变报告、几何或求解权重，仅提供优先检查顺序；停滞、初值或迭代预算也可能产生这些症状，不是无解证明或最小冲突集。示例与边界见[失败诊断](DIAGNOSTICS.md)及[可执行示例](../README.mbt.md)。

错误通过 `SketchError` 的变体匹配：`ForeignHandle`、`ResourceLimit`、`InvalidConstraint(id)`、`DegenerateLine(id)`、`InvalidRadius(id)` 等；`error.message()` 提供日志文本。[错误分类与 String API 迁移](API_GUIDE.md#类型化错误与迁移)说明完整语义。可用 `Sketch::constraint(finding.id)` 从残差找回原始关系，用 `SolveReport::residual(id)` 查询指定约束的结果，便于在编辑器中定位。

约束索引是同一草图内稳定、不复用的创建编号。删除后编号可能不连续，`report.residuals[id.index()]` 不再表示指定约束，请使用 `report.residual(id)`。旧报告属于求解当时的快照；若关系后来已删除，当前草图的 `constraint(id)` 返回 `None`。

## 容差与选项

默认调用 `sketch.solve_and_apply()` 即可。只有需要调整精度或预算时才传 `options`：

| 选项 | 默认值 | 接受范围 |
| --- | --- | --- |
| `length_tolerance` | `1e-7` | 必须为有限正数；除以草图尺度后在 `[1e-14,1e6]` |
| `angular_tolerance` | `1e-8` | `[1e-14,0.1]` |
| `rank_tolerance` | `1e-9` | `[1e-14,0.01]`，仅高级秩诊断 |
| `max_iterations` | `200` | `1..1000` |

```moonbit
let options = { ..@sketch.SolveOptions::default(), max_iterations: 300 }
let result = sketch.solve(options~)
```

长度沿用调用者统一单位，角度使用弧度。固定位置也按容差求解；返回坐标会重新核对残差。未收敛时可检查候选几何，但 `solve_and_apply()` 不保存它。欠约束的自由方向可能漂移，并无“离初值最近”的目标。

类型化错误处理见 [DIAGNOSTICS](DIAGNOSTICS.md#类型化错误与迁移)，输入边界见 [LIMITATIONS](LIMITATIONS.md)。归一化、自动微分与线性代数属于[内部实现](ARCHITECTURE.md#数值求解)。
