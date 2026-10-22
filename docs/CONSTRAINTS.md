# 几何与约束参考

| 类别 | 构造器 | 语义 |
| --- | --- | --- |
| 位置 | `Fix`、`Coincident` | 固定点坐标、两点重合，各产生两个方程 |
| 中心对称 | `Symmetric(a, b, center)` | `a+b=2*center`，两点关于第三点中心对称，产生两个方程 |
| 轴对称 | `Mirror(a, b, axis)` | 关于无限延伸直线镜像，产生两个长度方程；轴端点反向不影响关系 |
| 轴向 | `Horizontal`、`Vertical` | 线段端点的 y / x 相等 |
| 尺寸 | `Distance`、`DistanceX`、`DistanceY`、`DistanceToLine` | 两点距离；有符号的 `b.x-a.x`、`b.y-a.y`；点到有向无限直线的垂直距离，左侧为正 |
| 方向 | `Parallel`、`Perpendicular`、`Angle` | 平行、垂直、从第一条有向线到第二条的逆时针夹角 |
| 线关系 | `EqualLength`、`LengthRatio`、`Midpoint`、`PointOnLine` | 等长、`length(a)=ratio*length(b)`、中点、点在无限延伸直线上 |
| 圆尺寸 | `Radius`、`EqualRadius` | 半径、等半径 |
| 圆关系 | `Concentric`、`PointOnCircle` | 同心、点在圆周上 |
| 相切 | `Tangent`、`ExternalTangent`、`InternalTangent(outer, inner)` | 无限直线与圆相切、两圆外切、指定外圆与内圆的内切 |

共 24 种约束。`Distance(..., 0)` 使用两个坐标差方程，避免零距离范数的奇异导数。`Parallel` 同时接受同向和反向线；`Angle` 区分有向线。圆弧、样条和不等式约束暂未实现。

本轮聚焦 `Point`、`Line`、`Circle`，持续验证稳定性并维护 Benchmark，优先完善包与版本交付。`Arc` 仅列为可选 P1，时间不足可跳过；椭圆、Bezier、Spline、NURBS 和独立 Polygon 类型暂缓。具体安排见[几何扩展优先级](POSITIONING.md#几何扩展优先级)。

`Mirror(a, b, axis)` 使两点的沿轴坐标相等、其中点到轴的带符号距离为零，两个残差都使用长度容差。允许两点在轴上重合；`Mirror(p, p, axis)` 等价于点落在轴上，仍保留沿轴自由度。轴需要非退化，不会自动固定；需固定轴时应约束端点。镜像圆可组合圆心的 `Mirror` 与半径的 `EqualRadius`。

`InternalTangent(outer, inner)` 要求两圆心距离等于 `outer.radius-inner.radius`。外圆半径在初值和迭代中均须大于内圆，差值超过草图尺度的 `1e-12`；等半径圆不作为孤立内切接受。初始圆心重合时可能停滞，宜先设置不同圆心。

## 添加与编辑

保存 `constrain()` 返回的 `ConstraintId`。`set_constraint()` 替换关系，`set_constraint_enabled()` 临时启停，`remove_constraint()` 永久删除。删除后其他创建编号保持不变，新关系不复用旧编号。禁用关系跳过关系校验及求解，但仍占现存约束名额；几何对象始终校验。

编辑初值不等于固定尺寸。保持位置使用 `Fix`，驱动半径使用 `Radius`，驱动两点距离使用 `Distance`。所有启用关系共同求解；没有软约束优先级。

[约束生命周期](CONSTRAINT_LIFECYCLE.md)给出完整行为与边界；[快速开始](QUICK_START.md)展示添加和修改尺寸，[限制](LIMITATIONS.md)列出范围，[求解](SOLVER.md)解释结果状态。
