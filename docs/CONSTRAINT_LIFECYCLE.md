# 约束生命周期与永久删除

~~~moonbit
pub fn Sketch::remove_constraint(
  self : Sketch,
  id : ConstraintId,
) -> Bool
~~~

`s.remove_constraint(id)` 从草图永久删除一条现存约束。它不修改点、线或圆，不会自动求解；下一次求解时该关系不再参与校验、尺度计算、方程、局部自由度或残差报告。

## 编辑流程

```moonbit
let relation = s.constrain(Distance(a, b, 20.0))
s.set_constraint(relation, Distance(a, b, 30.0)) |> ignore
s.set_constraint_enabled(relation, false) |> ignore
s.set_constraint_enabled(relation, true) |> ignore
s.remove_constraint(relation) |> ignore
```

这里的 a、b 是调用者已创建的点。完整可运行版本及断言见 [README.mbt.md](../README.mbt.md) 中的删除示例，并随 moon test 执行。

| 操作 | 禁用的约束 | 已删除的约束 |
| --- | --- | --- |
| constraint(id) | 返回原关系 | None |
| constraint_enabled(id) | Some(false) | None |
| set_constraint(id, ...) | 可以修改，继续保持禁用 | false |
| set_constraint_enabled(id, true) | 恢复参与求解 | false |
| remove_constraint(id) | true，永久删除 | false |
| 下一份 SolveReport | 保留一条 active=false、误差为零的记录 | 不包含该关系 |
| 512 条约束的上限 | 仍占一个名额 | 释放名额 |

成功删除返回 true。未知、负编号、其他草图的句柄以及重复删除返回 false，草图保持不变。删除无需先让关系通过数值或引用校验，因此可以清理导致 solve() 返回 Err 的非法约束；草图中剩余的几何和约束仍须合法。

## 句柄与报告

约束编号在同一 Sketch 中按创建顺序递增，删除不会改动其他约束的编号，新建关系也不会复用旧编号。删除前的句柄永久失效；需要恢复同样关系时，应再次 constrain() 并保存新句柄。库没有撤销栈，应用若需要撤销应另行保存原关系。

ConstraintId::index() 是稳定的创建编号，**不是删除后残差数组的下标**。报告的 residuals 数组仅包含求解时仍存在的关系，按原创建顺序排列，可能出现编号空缺。请用 report.residual(id) 或遍历每条记录的 id 查找，避免 residuals[id.index()]。

| 查询时刻 | 当前草图 constraint(id) | 旧报告 residual(id) | 删除后新报告 residual(id) |
| --- | --- | --- | --- |
| 删除已存在的关系后 | None | 保留求解当时的残差和 active 状态 | None |

旧报告是历史快照，删除、修改或启停不会重写它。报告不保存原 Constraint 对象；删除后无法再通过当前草图找回这个旧关系。旧报告的 unsatisfied() 也仍然描述历史求解，界面应区分历史诊断和当前模型。

## 几何、自由度与资源边界

删除关系只改变约束集合，当前坐标与半径逐项保留。之后重新求解时，自由度可能增加；残差达标仍可能是欠约束结果。原有规则继续适用：solve() 不应用结果，solve_and_apply() 仅在全部启用关系达到容差时更新几何。

最多 512 条**现存关系**，包括禁用关系，不包括已删除关系。累计创建次数可以超过 512；内部会移除已删除记录，不按历史最高编号分配残差数组。与之前一致，添加过多现存关系后，资源错误在 solve() 时报告；可以删除关系使模型回到上限内。

约束 ID 使用 Int32 创建编号，达到编号空间末端时 constrain() 中止，避免溢出后重新指向旧对象。句柄仍只适用于同一运行时、同一草图，不能当作持久化标识。

内部采用紧凑的关系 / 启停 / 句柄数组，查找与删除为 O(n)。这里的 n 是现存关系数，接受求解的模型最多为 512；该 API 没有引入增量线性求解、软约束优先级、几何对象删除或自动约束清理。

## 验证证据

[removal_wbtest.mbt](../removal_wbtest.mbt) 覆盖：

- 活跃冲突删除，以及删除前后当前几何完全相同。
- 首项、中间项、末项、禁用项和最后一条关系的删除。
- 删除尺寸后的局部自由度变化，以及新关系重新驱动几何。
- 相邻关系的启停状态、稀疏编号的查询、历史报告与当前报告隔离。
- 跨草图、负编号、未知句柄与重复删除的拒绝行为。
- 删除非法引用、NaN 或极端尺寸后，不再影响校验与归一化。
- 禁用关系仍计入 512 上限；删除后可补充关系。
- 1024 次添加删除循环不复活旧句柄、不占用历史名额。
- 编号接近 Int32 上限时，报告仍只存一条实际关系。
- 删除导致数组压缩后，校验和求值错误仍报告稳定的约束编号。

此外，[公开接口示例](../README.mbt.md) 验证完整生命周期，[源码包消费检查](../scripts/check_package.py) 从实际分发 ZIP 解包后，通过独立模块调用 remove_constraint() 并检查新旧报告。安装板和四杆机构案例继续验证现有编辑行为。
