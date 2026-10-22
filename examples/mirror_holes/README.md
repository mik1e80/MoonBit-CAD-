# Mirror Holes：镜像孔位

在仓库根目录运行 `moon run examples/mirror_holes --target js`。

[main.mbt](main.mbt)通过 `Mirror` 与 `EqualRadius` 建立两孔：左孔 (6,3)、轴 x=10 时右孔为 (14,3)，两孔半径为 2。将轴移到 x=12 后右孔为 (18,3)。程序检查实际求解坐标、半径和局部自由度，并验证冲突编辑不改变保存几何，停用冲突关系后恢复；检查失败以非零状态退出。

几何关系定义见 [约束参考](../../docs/CONSTRAINTS.md)，错误和报告说明见 [诊断](../../docs/DIAGNOSTICS.md)。
