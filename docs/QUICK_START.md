# 快速开始

创建几何 → 添加约束 → 求解 → 编辑尺寸 → 查看诊断。以下命令均在仓库根目录执行。

## 安装与版本

当前版本 `0.2.1`：[Mooncakes 包页面](https://mooncakes.io/docs/mik1e80/cad_sketch)。源码仓库：[moonbit-cad-sketch](https://github.com/mik1e80/moonbit-cad-sketch)。模块名：`mik1e80/cad_sketch`。

在已有 MoonBit 项目的根目录运行：

```sh
moon add mik1e80/cad_sketch
```

该命令从注册表下载模块，并写入当前项目的 `moon.mod` 依赖。然后按下文配置使用方的 `moon.pkg` 导入核心包。

工具链要求：`moonc >= 0.10.15`，已在 `moon 0.1.20261012` / `moonc 0.10.15+943464bfa` 上验证。源码采用新版 `Int32` 与带默认值的标记参数语法；旧版 0.10.14 需要先更新工具链。

如果希望修改源码或运行仓库内案例：

```sh
git clone https://github.com/mik1e80/moonbit-cad-sketch.git
cd moonbit-cad-sketch
moon test README.mbt.md --target js
moon run examples/basic
```

源码开发也可使用下文的本地 workspace；示例及核心库只需要 MoonBit。Node.js 和 Python 仅用于可选的开发验证。

## 第一个草图

日常使用只需：创建几何 → 添加约束 → 求解 → 编辑尺寸 → 查看诊断。默认选项即可开始；[API 使用指南](API_GUIDE.md)按这五步介绍接口。

在使用者的 `moon.pkg` 中导入：

```moonbit
import {
  "mik1e80/cad_sketch" @sketch,
}
```

下面这段示例也作为公开接口测试运行，完整版本见 [README.mbt.md](../README.mbt.md)。

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
    } else {
      for finding in solution.report.likely_conflicts() {
        println("约束 #\{finding.id.index()}：误差比 \{finding.tolerance_ratio}")
      }
    }
  }
  Err(error) => println(error.message())
}

// 修改尺寸后，以已有坐标为初值继续求解。
if s.set_constraint(dimension, Distance(a, b, 7.0)) {
  match s.solve_and_apply() {
    Ok(updated) => println("修改尺寸后达标：\{updated.report.is_satisfied()}")
    Err(error) => println(error.message())
  }
}
```

进行源码开发时，可使用 MoonBit 的[本地 workspace](https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html#local-dependencies) 调用源码。在共同父目录创建 `moon.work`，例如 `members = ["moonbit-cad-sketch", "my_app"]`；在 `my_app/moon.mod` 添加 `import { "mik1e80/cad_sketch@0.2.1" }`，再按上面的 `moon.pkg` 导入。workspace 优先解析本地成员。普通使用者直接用上面的 `moon add` 安装即可。

## 运行案例

| 目录 | 命令 | 观察内容 |
| --- | --- | --- |
| [basic](../examples/basic/README.md) | `moon run examples/basic --target js` | 矩形改宽、三角形与相切圆 |
| [parametric_bracket](../examples/parametric_bracket/README.md) | `moon run examples/parametric_bracket --target js` | 板宽、孔径、边距联动 |
| [mirror_holes](../examples/mirror_holes/README.md) | `moon run examples/mirror_holes --target js` | 镜像孔与对称轴移动 |
| [four_bar](../examples/four_bar/README.md) | `moon run examples/four_bar --target js` | 同一机构连续改变角度 |
| [conflict](../examples/conflict/README.md) | `moon run examples/conflict --target js` | 打印误差比、停用及删除冲突关系 |

修改驱动尺寸使用 `set_constraint()`，直接移动初值使用 `set_point()` / `set_radius()`。查询或编辑返回 `None` / `false` 时先检查句柄归属；所有句柄仅属于创建它的草图。

继续阅读：[约束参考](CONSTRAINTS.md)、[求解与结果](SOLVER.md)、[错误与诊断](DIAGNOSTICS.md)、[限制](LIMITATIONS.md)。
