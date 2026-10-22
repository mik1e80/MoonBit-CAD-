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

两个求解方法都返回 `Result[Solution,SketchError]`。先按错误变体处理 `Err(error)`，日志使用 `error.message()`，再在 `Ok(solution)` 中检查 `solution.report.is_satisfied()`：

- `Err`：输入或求值出错，读取错误信息修正输入。
- `Ok` 且达标：用 `sketch.point(id)`、`sketch.radius(id)` 读取更新后的草图；也可用 `solution.point(id)`、`solution.radius(id)` 读取返回结果。
- `Ok` 但未达标：查看报告并调整初值、尺寸或约束。`Stalled` / `IterationLimit` 不证明无解。

`solve_and_apply()` 只在全部启用关系达到容差时更新几何。`solve()` 始终保留当前草图，只返回候选结果；未达标的候选几何可以检查，但不能当成已经保存的草图。基本调用不需要传 `options`。

## 类型化错误与迁移

`solve()` 与 `solve_and_apply()` 返回 `Result[Solution,SketchError]`。这是源码 API 变更：显式声明的 `Result[Solution,String]` 需要替换错误类型；原先打印或 `abort(message)` 的调用改用 `error.message()`。不应解析消息文本判断错误类别。

| 变体 | 含义 |
| --- | --- |
| `InvalidGeometry(String)` | 点坐标非法，或本草图几何引用缺失 |
| `InvalidConstraint(ConstraintId)` | 启用关系的引用、尺寸或几何定义域非法；含删除后仍稳定的创建句柄 |
| `ForeignHandle` | 几何或启用关系使用其他草图的句柄 |
| `DegenerateLine(LineId)` | 初始或求值时线长退化 |
| `InvalidRadius(CircleId)` | 圆的初始或求值半径非法、相对尺度过小 |
| `ResourceLimit` | 超过变量、线或现存约束上限 |
| `InvalidOptions(String)` | 容差、相对尺度或迭代预算非法 |
| `NumericalFailure(String)` | 非有限求值或输出溢出 |

```moonbit
match sketch.solve_and_apply() {
  Err(ForeignHandle) => println("请使用同一草图的句柄")
  Err(ResourceLimit) => println("请拆分草图")
  Err(InvalidConstraint(id)) => println("检查约束编号 \{id.index()}")
  Err(error) => println(error.message())
  Ok(solution) => println(solution.report.is_satisfied())
}
```

禁用关系仍跳过关系校验，几何对象始终校验。多个问题同时存在时返回按校验顺序遇到的第一个错误，并不汇总所有错误。迭代搜索中的非法候选会被拒绝；最终未收敛使用 `Ok` 内的 `Stalled` / `IterationLimit`。`Err` 和未达标结果均不会由 `solve_and_apply()` 写回几何。JSON 示例工具仍将 `message()` 序列化为字符串，因此其数据格式保持一致。

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
