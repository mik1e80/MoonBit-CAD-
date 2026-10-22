# 可运行示例

从仓库根目录运行；默认示例只依赖 MoonBit，`--target js` 显式选择 JS 后端。

| 示例 | 命令 | 内容 |
| --- | --- | --- |
| [basic](basic/README.md) | `moon run examples/basic --target js` | 矩形尺寸编辑、三角形和圆相切 |
| [parametric_bracket](parametric_bracket/README.md) | `moon run examples/parametric_bracket --target js` | 四孔参数化安装板 |
| [mirror_holes](mirror_holes/README.md) | `moon run examples/mirror_holes --target js` | 镜像孔位与移动对称轴 |
| [four_bar](four_bar/README.md) | `moon run examples/four_bar --target js` | 四杆机构连续角度驱动 |
| [conflict](conflict/README.md) | `moon run examples/conflict --target js` | 诊断、失败保留与恢复 |

这些目录中的 `main.mbt` 使用核心库公开接口。安装与导入见 [快速开始](../docs/QUICK_START.md)。原命令路径 `cmd/demo`、`cmd/bracket_demo`、`cmd/mirror_demo` 分别迁移到前三个目录；旧路径不再提供入口。
