# 失败诊断与优先排查

```moonbit
pub fn SolveReport::likely_conflicts(
  self : SolveReport,
) -> Array[ConstraintResidual]
```

`report.likely_conflicts()` 提供启发式排查顺序，便于在界面或日志中优先显示超出容差最多的关系。可运行并打印编号、关系类型和误差比的例子见 [README.mbt.md](../README.mbt.md)；该示例随 `moon test` 执行。

## 返回规则

1. 仅保留 `active == true` 且 `tolerance_ratio > 1.0` 的记录，与 `unsatisfied()` 成员相同。
2. 按 `tolerance_ratio` 从大到小排列；相同误差比按稳定约束编号从小到大排列，确保重复调用结果一致。
3. 返回完整的新数组。调用者可自行选择显示前几项；修改返回数组不影响报告。

每条记录保留原有 `id`、`active`、`length_error`、`angular_error` 和 `tolerance_ratio`。`unsatisfied()` 和 `residuals` 继续使用报告原顺序，按 ID 查询的 `residual(id)` 也保持原行为。

误差比是该关系各残差分量除以对应容差后的最大绝对值：长度分量使用长度容差，角度 / 方向分量使用角度容差。因此排序比较的是超出各自容差的程度，不能直接按原始长度误差和角度误差的大小比较。比值等于 1 时达标，不进入列表；禁用关系也不进入列表。

## 解释结果

列表用于回答“先检查哪些关系”，不能证明哪些关系共同导致无解，更不是最小不可满足集（MUS）。高误差关系可能只是别的关系造成的症状；多个矛盾组也未必全部出现在当前超标项中。排序不赋予软约束权重或优先级，不会自动关闭、删除、修改约束或再次求解。

非线性求解的初值、尺度、构型和迭代预算都可能导致停滞。例子：两个点初始重合，却要求正距离，可能因奇异导数停滞；适当分开初始点后，同一组约束可以求解。因此 `likely_conflicts()` 非空也不构成无解证明。相反，空列表只说明报告中没有启用超标项，不能证明全局刚性或唯一解。

调用者应结合求解状态、原始关系和候选几何判断。失败的 `solve_and_apply()` 保留草图原几何；报告描述返回的候选结果，未必是当前保存几何的误差。使用 `sketch.constraint(finding.id)` 可以查看当前关系，使用 `report.residual(finding.id)` 查看这份报告的记录。

## 编辑与历史快照

该方法只读取报告，不修改草图或报告。报告生成后若删除、启停或修改了关系，旧报告依然描述当时的状态，调用者应重新求解以获得当前诊断。删除后的旧关系可能仍出现在历史排序中，而当前 `sketch.constraint(id)` 已返回 `None`；应在界面上区分历史结果和当前草图。

稳定 ID 不等于数组下标。永久删除使编号出现空缺，但不影响排序、查询或其他关系的身份。详见[约束生命周期](CONSTRAINT_LIFECYCLE.md)。

输入或求值非法而返回 `Err` 时没有 `SolveReport`，需处理原错误信息；本方法不把输入错误转换成冲突候选。

## 验证

[diagnostics_wbtest.mbt](../diagnostics_wbtest.mbt) 覆盖加权误差排序、并列编号顺序、容差边界、禁用项过滤、独立返回数组、空 / 欠约束 / 冗余模型、真实矛盾与删除恢复、历史快照、可解模型的奇异初值及无穷大误差比的确定性排序。

[README.mbt.md](../README.mbt.md) 提供可执行公开接口示例，[源码包检查](../scripts/check_package.py) 在独立消费模块中验证带编号空缺的实际矛盾诊断。现有求解规则与数值限制见 [README](../docs/LIMITATIONS.md)。


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


## 运行冲突案例

`moon run examples/conflict --target js` 打印真实求解报告中的约束编号与误差比，验证未达标时原几何不变，再演示停用和永久删除后的恢复。代码与预期行为见 [conflict](../examples/conflict/README.md)。
