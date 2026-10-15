# MoonBit CAD Sketch

纯 MoonBit 的二维 CAD 草图约束求解库。输入点、线、圆和尺寸关系，求解坐标与半径，并报告约束残差及局部自由度。

适合参数化零件草图、尺寸联动和小型平面连杆机构。核心库仅使用 MoonBit core，不需要 C/C++ 求解器、FFI 或 JavaScript 数学库。支持 wasm、wasm-gc、JS 和 native。

## 当前版本

第一版源码版本 `0.1.0`，尚未发布到 Mooncakes。仓库：<https://github.com/mik1e80/MoonBit-CAD->。模块名：`mik1e80/cad_sketch`。

工具链要求：`moonc >= 0.10.15`，已在 `moon 0.1.20261012` / `moonc 0.10.15+943464bfa` 上验证。源码采用新版 `Int32` 与带默认值的标记参数语法；旧版 0.10.14 需要先更新工具链。

```sh
git clone https://github.com/mik1e80/MoonBit-CAD-.git
cd MoonBit-CAD-
moon test
moon run cmd/demo
```

`cmd/demo` 实际求解 10×6 矩形，将宽度改成 15 后再次求解，再演示 3-4-5 三角形、两圆外切以及互相矛盾的坐标约束。

## 使用示例

在使用者的 `moon.pkg` 中导入：

```moonbit
import {
  "mik1e80/cad_sketch" @sketch,
}
```

下面这段示例也作为公开接口测试运行，完整版本见 [README.mbt.md](README.mbt.md)。

```moonbit
let s = @sketch.Sketch::new()
let a = s.add_point(0.0, 0.0)
let b = s.add_point(3.0, 0.5)
let line = s.add_line(a, b)
s.constrain(Fix(a, 0.0, 0.0)) |> ignore
s.constrain(Horizontal(line)) |> ignore
let dimension = s.constrain(Distance(a, b, 5.0))

match s.solve_and_apply() {
  Ok(solution) => {
    if solution.report.is_satisfied() {
      let p = s.point(b).unwrap()
      println("B = (\{p.x}, \{p.y})") // 接近 (5, 0)
    }
  }
  Err(message) => println(message)
}

// 修改尺寸后，以已有坐标为初值继续求解。
s.set_constraint(dimension, Distance(a, b, 7.0)) |> ignore
```

发布前，如需从另一模块调用，可使用 MoonBit 的[本地模块路径依赖](https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html)。不要把 `moon add mik1e80/cad_sketch` 当作已经可用的安装命令。

## 支持的约束

| 类别 | 构造器 | 语义 |
| --- | --- | --- |
| 位置 | `Fix`、`Coincident` | 固定点坐标、两点重合，各产生两个方程 |
| 轴向 | `Horizontal`、`Vertical` | 线段端点的 y / x 相等 |
| 尺寸 | `Distance`、`DistanceX`、`DistanceY` | 两点距离；有符号的 `b.x-a.x`、`b.y-a.y` |
| 方向 | `Parallel`、`Perpendicular`、`Angle` | 平行、垂直、从第一条有向线到第二条的逆时针夹角 |
| 线关系 | `EqualLength`、`Midpoint`、`PointOnLine` | 等长、中点、点在无限延伸直线上 |
| 圆尺寸 | `Radius`、`EqualRadius` | 半径、等半径 |
| 圆关系 | `Concentric`、`PointOnCircle` | 同心、点在圆周上 |
| 相切 | `Tangent`、`ExternalTangent` | 无限直线与圆相切、两圆外切 |

共 19 种约束。`Distance(..., 0)` 使用两个坐标差方程，避免零距离范数的奇异导数。`Parallel` 同时接受同向和反向线；`Angle` 区分有向线。圆内切、圆弧、样条、对称和不等式约束暂未实现。

## 求解与诊断

- `Sketch::solve()` 返回 `Result[Solution, String]`，保留原草图。
- `Sketch::solve_and_apply()` 只在全部约束达到容差时更新坐标与半径；失败时保留原草图。
- `Solution::point()` / `radius()` 可读取结果，也可检查未收敛时的最后一个被接受的迭代结果。句柄只属于创建它的草图。
- `set_point()` 修改下一次求解的初值；`set_constraint()` 修改已有尺寸或关系。它们返回是否找到相应句柄，数值合法性在 `solve()` 时统一验证。
- `set_radius()` 修改已有圆的初始半径，保留中心与关联约束；它不固定半径，驱动半径尺寸应使用 `Radius`。非法数值同样在求解时诊断。
- `set_constraint_enabled(id, false)` 暂停某条约束，传 `true` 恢复；编号与关系保留，`set_constraint()` 不改变启停状态。禁用关系不参与校验、尺度计算、方程和自由度计算，仍计入 512 条关系的存储上限；几何本身始终需要合法。

`SolveReport` 包含：

| 字段 | 含义 |
| --- | --- |
| `status` | `Satisfied`：返回几何的每个残差分量均达标；`Stalled`：无法继续降低误差或输出坐标精度不足；`IterationLimit`：达到迭代次数上限 |
| `local_dof` | 变量数减去当前雅可比矩阵的数值秩 |
| `dependent_equations` | 方程数减去数值秩，表示当前点的一阶方程依赖 |
| `residuals` | 每条约束的启用状态 `active`、最大长度误差、角度 / 方向误差、误差与容差之比；禁用项误差置零，仅表示未检查 |
| `unsatisfied()` | 误差与容差之比大于 1 的约束 |

`Err` 表示非法尺寸、失效引用、退化初值、资源上限或数值求值错误。**未收敛不证明无解，未满足约束列表也不是最小冲突集。** 重复约束可以被同时满足。奇异构型的一阶自由度可能高于实际运动自由度，例如完全共线的三角形；不要把它当成全局刚性证明。

输入与求值错误会注明点、线、圆或约束的索引。可用 `Sketch::constraint(finding.id)` 从残差找回原始关系，用 `SolveReport::residual(id)` 查询指定约束的结果，便于在编辑器中定位。

## 数值范围与边界

采用带列缩放和阻尼的 Gauss–Newton 迭代。前向自动微分计算雅可比，增广系统通过 Givens QR 求解，不显式形成正规方程。平移和统一长度缩放用于改善数值条件。求解结束后，按实际返回的 Double 坐标重新计算报告，防止大坐标舍入导致虚假的成功结果。

默认 `SolveOptions`：长度容差 `1e-7`、角度 / 方向容差 `1e-8`、数值秩阈值 `1e-9`、最多 200 次迭代。长度沿用调用者单位；`Angle` 使用弧度，平行 / 垂直的方向残差分别为单位向量的叉积 / 点积。固定坐标同样受长度容差约束，并非精确算术常量。

- 面向小型草图：最多 256 个标量变量、512 条线、512 条约束。点占 2 个变量，圆半径另占 1 个变量；同一中心点可复用。
- 坐标及长度输入必须有限，绝对值不超过 `1e100`。距离非负、半径严格为正；角度在 `[-2π, 2π]`。
- 长度容差 / 草图尺度需在 `[1e-14, 1e6]`；角度容差 `[1e-14, 0.1]`，秩阈值 `[1e-14, 0.01]`，迭代预算 `1..1000`。
- 初始线长不得为零。迭代中线长必须大于草图尺度的 `1e-12`，半径必须大于尺度的 `1e-14`。极端大小混合的模型可能被拒绝。
- 非线性问题可能多解、翻转或停滞。初始几何应接近所需构型；改尺寸时可分小步求解。两点重合时再要求正距离，是可能停滞的奇异初值，可先分开两点。
- 当前使用稠密矩阵，每次求解重新线性化；没有稀疏增量求解、全局搜索、拖拽优先级、约束删除、最小冲突证明和大型装配求解。
- 这是一套库及命令行示例，尚未提供完整 CAD 编辑器、文件导入导出或 DXFKIT 集成。

## 验证

```sh
moon fmt --check
moon check --target all --deny-warn
moon build
moon test
moon test --target wasm-gc
moon test --target js
moon test --target native
moon run cmd/demo
```

测试包含不同尺寸与平移下的矩形、解析可验的三角形和夹角、两侧线圆相切、圆关系、修改尺寸、连续 21 个曲柄位置的四杆机构，以及冗余、矛盾、奇异初值、输出舍入和资源限制。所有约束的自动微分导数另外与中心差分对照；QR 和数值秩也有独立构造案例。测试通过不代表任意非线性草图均会收敛。

## 与相关项目的区别

| 项目 | 范围 | 本项目的关系 |
| --- | --- | --- |
| [SolveSpace](https://solvespace.com/tech.pl) | 成熟的参数化 CAD 及几何约束求解器，包含二维、三维和更多实体 | 作为需求与行为参照；本项目是独立实现的小型二维 MoonBit 库，未移植其代码，不宣称功能或稳健性等价 |
| [sgy1023-crt/cassowary](https://mooncakes.io/docs/sgy1023-crt/cassowary) | MoonBit 增量线性约束库，包含优先级与编辑变量 | 本项目处理距离、夹角、相切等非线性几何等式；暂不支持 Cassowary 的增量编辑与软约束优先级 |
| [mik1e80/dxfkit](https://github.com/mik1e80/dxfkit) | DXF 读取、几何离散、辅助检查和 SVG 预览 | 本项目修改参数化草图几何，不负责读取或检查 DXF；当前没有自动互转接口 |

## 许可与来源

Apache-2.0，完整条款见 [LICENSE](LICENSE)。实现与测试为本仓库编写，没有打包第三方样例或求解器代码。算法出处、参考文档与范围说明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
