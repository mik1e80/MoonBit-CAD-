# Conflict：诊断与恢复

在仓库根目录运行 `moon run examples/conflict --target js`。

[main.mbt](main.mbt)向同一点添加 (0,0) 与 (10,0) 两条 `Fix`，读取真实报告，打印稳定约束编号与 `tolerance_ratio`。示例检查未达标时保存坐标仍为初值 (2,3)，停用冲突关系后恢复，重新启用后再次未达标，永久删除后恢复到原点附近。预期不符会以非零状态退出。

排序列表是启发式检查顺序，不是最小冲突集。一般的 `Stalled` / `IterationLimit` 不证明无解；输入错误则通过 `SketchError` 返回。完整语义见 [DIAGNOSTICS](../../docs/DIAGNOSTICS.md)，编辑行为见 [约束生命周期](../../docs/CONSTRAINT_LIFECYCLE.md)。
