# API 使用指南

从 `Sketch::new()` 开始，定义点、线、圆，添加设计关系，然后调用 `solve_and_apply()`。修改尺寸后再次求解；需要排查时读取报告。默认选项即可完成这条流程。

## 五类接口

| 工作 | 常用接口 | 作用 |
| --- | --- | --- |
| Geometry：几何 | `Sketch::new()`、`add_point()`、`add_line()`、`add_circle()` | 建立草图，保存返回的实体句柄 |
| Constraint：约束 | `constrain(Horizontal(line))`、`constrain(Distance(a,b,value))` 等 | 描述设计关系，保存需要编辑的约束句柄 |
| Solve：求解 | `solve_and_apply()`、`solve()` | 求解并在达标时更新几何，或只查看候选结果 |
| Edit：编辑 | `set_constraint()`、`set_constraint_enabled()`、`remove_constraint()` | 修改关系、临时启停或永久删除，再次求解 |
| Diagnostic：诊断 | `report.is_satisfied()`、`unsatisfied()`、`likely_conflicts()`、`residual(id)` | 检查是否达标，查找需要排查的关系 |

[README 的完整入门示例](../README.md#使用示例)演示了一条水平线段：创建点和线 → 固定起点 → 设置长度 → 求解 → 修改长度再求解。[README.mbt.md](../README.mbt.md)提供可执行公开接口示例，覆盖尺寸编辑、启停、删除、诊断和镜像。

## 创建几何与约束

`add_point(x,y)` 的坐标是初值；`add_line(a,b)` 连接已存在的两个点；`add_circle(center,radius)` 使用已有中心点和初始半径。需要固定位置或半径时，用 `Fix` 或 `Radius` 表达关系。

例如 `Horizontal(line)` 表示水平，`Distance(a,b,5.0)` 表示两点距离。调用者选择几何关系和目标尺寸，库完成后续求解。全部关系及单位约定见[约束表](../README.md#支持的约束)；距离沿用调用者单位，角度使用弧度。

## 求解和读取结果

两个求解方法都返回 `Result[Solution,String]`。先处理 `Err(message)`，再在 `Ok(solution)` 中检查 `solution.report.is_satisfied()`：

- `Err`：输入或求值出错，读取错误信息修正输入。
- `Ok` 且达标：用 `sketch.point(id)`、`sketch.radius(id)` 读取更新后的草图；也可用 `solution.point(id)`、`solution.radius(id)` 读取返回结果。
- `Ok` 但未达标：查看报告并调整初值、尺寸或约束。`Stalled` / `IterationLimit` 不证明无解。

`solve_and_apply()` 只在全部启用关系达到容差时更新几何。`solve()` 始终保留当前草图，只返回候选结果；未达标的候选几何可以检查，但不能当成已经保存的草图。基本调用不需要传 `options`。

## 编辑后重新求解

保存 `constrain()` 返回的句柄，之后可调用：

```moonbit
// dimension 是已有 Distance 关系的句柄；a、b 是同一草图的点。
sketch.set_constraint(dimension, Distance(a, b, 7.0)) |> ignore
// 接着调用 sketch.solve_and_apply()，按上面的 Result 与达标状态处理。
```

`set_point()` 和 `set_radius()` 改变下一次求解的初值，不固定这些数值；驱动设计尺寸应修改对应的约束。编辑方法返回 `Bool` 表示句柄是否找到，数值合法性在求解时检查。

临时停用用 `set_constraint_enabled(id,false)`，恢复用 `true`；永久删除用 `remove_constraint(id)`。删除不改变其他关系编号，旧句柄不能重新启用，新建关系会得到新句柄。详细语义见[约束生命周期](CONSTRAINT_LIFECYCLE.md)。

## 按需查看诊断

`is_satisfied()` 是常用入口。`local_dof` 表示当前构型下估计的剩余自由度；达标时仍可能欠约束。需要定位问题时，查看：

- `unsatisfied()`：启用但超出容差的关系，保留报告原顺序。
- `likely_conflicts()`：相同超标项，按误差比降序排列，提供优先排查顺序。
- `residual(id)`：指定关系在这份报告中的残差。
- `sketch.constraint(id)`：该句柄当前对应的关系。

排序列表不是最小冲突集，也不代表应自动删除哪些关系。报告是求解时的快照，后续编辑不会重写它；查看当前模型应重新求解。详细说明见[失败诊断](DIAGNOSTICS.md)。

句柄只属于创建它的草图；删除或查询失败时处理 `false` / `None`。不要把创建编号当作残差数组下标，也不要将它当作跨进程持久化标识。

## 进阶入口

日常建模只需上述默认流程。需要调整容差、迭代预算或理解高级报告时，参阅[内部实现与数值设置](ARCHITECTURE.md)；规模和输入限制见 [README 边界说明](../README.md#数值范围与边界)。这些进阶内容不要求调用者自行组装求解算法。
