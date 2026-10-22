# Parametric Bracket：四孔安装板

在仓库根目录运行 `moon run examples/parametric_bracket --target js`。同一草图输出初始、加宽、扩大孔、修改边距、冲突和恢复六个阶段。

![实际求解结果](../../docs/images/bracket-before-after.svg)

[main.mbt](main.mbt)建立几何与关系；[bracket_wbtest.mbt](bracket_wbtest.mbt)额外检查板高和双向边距编辑。完整参数、约束、解析校验与 JSON 字段见 [Showcase 说明](../../docs/SHOWCASE.md)。

如需独立检查 SVG，运行 `node scripts/bracket_showcase.cjs --check --target js`；该命令需要 Node.js。它只验证这个案例，不运行全量套件。


案例的 JSON 事件包含核心 `Sketch::to_svg()` 返回的 `svg` 字符串。运行 `python scripts/export_svg.py --write` 写出独立的修改前、修改后及冲突 SVG；`--check` 只核对文件。接口和共享比例见 [SVG 导出](../../docs/SVG_EXPORT.md)。此功能已包含在 Mooncakes 0.2.1 正式版本中。
