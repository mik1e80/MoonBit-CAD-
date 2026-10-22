# API 使用指南

从 [快速开始](QUICK_START.md)进入：创建几何、添加关系、求解、修改尺寸，再按报告判断结果。

| 工作 | 接口 | 专题 |
| --- | --- | --- |
| Geometry | `Sketch::new()`、`add_point()`、`add_line()`、`add_circle()` | [快速开始](QUICK_START.md) |
| Constraint | `constrain()` 与 24 种关系构造器 | [约束参考](CONSTRAINTS.md) |
| Solve | `solve()`、`solve_and_apply()`、`Solution` | [求解与结果](SOLVER.md) |
| Edit | `set_constraint()`、`set_constraint_enabled()`、`remove_constraint()` | [约束生命周期](CONSTRAINT_LIFECYCLE.md) |
| Diagnostic | `SketchError`、`SolveReport`、`likely_conflicts()` | [错误与诊断](DIAGNOSTICS.md) |

## 类型化错误与迁移

`solve()` / `solve_and_apply()` 返回 `Result[Solution,SketchError]`。完整分类、模式匹配和 String API 迁移说明已整理到 [诊断文档](DIAGNOSTICS.md#类型化错误与迁移)。

## 进阶入口

范围与资源边界见 [LIMITATIONS](LIMITATIONS.md)。高级数值设置见 [SOLVER](SOLVER.md#容差与选项)，算法细节见 [ARCHITECTURE](ARCHITECTURE.md)。可执行公开接口示例保留在 [README.mbt.md](../README.mbt.md)。


## SVG 导出（源码开发版）

`Sketch::to_svg()` 返回当前保存几何的 SVG 字符串；可选设置画布、点标记、标题和共享视野。已发布的 Mooncakes 0.1.0 不含此新增接口。[完整用法与三阶段图形](SVG_EXPORT.md)说明校验、坐标方向和冲突保留语义。
