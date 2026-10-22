# Consumer Test：全新项目安装、测试与运行

这项检查使用已经发布的 `mik1e80/cad_sketch@0.1.0`。它在系统临时目录创建全新项目，从 Mooncakes 解析依赖，执行消费项目自身的两项测试，再运行可执行入口。它不运行本仓库的回归套件或后端矩阵。

## 一条命令复现

需要兼容的 MoonBit 工具链、Python 3.10+ 标准库以及注册表网络访问。在仓库根目录运行：

```sh
python scripts/check_consumer.py
```

[脚本](../scripts/check_consumer.py)执行真实的 `moon new`、`moon add`、`moon info`、`moon fmt`、`moon test` 和 `moon run`。消费项目不在仓库目录内，不存在 `moon.work` 或 path 依赖；安装前项目还没有 `.mooncakes` 目录。在线索引刷新失败时检查失败，正常 Moon 注册表缓存可以复用，是否命中缓存会写入结果。无需登录或发布权限。

成功后生成 `_build/consumer-test/latest.json`；终端显示仓库外的临时项目与逐命令日志位置，保留文件便于检查。消费程序仅导入已安装的公开包。默认只检查 JS 后端，只有两项小测试和一次示例运行。

## 手工复现

在仓库及任何本地 Moon workspace 之外，创建一个新目录并进入，然后运行：

```sh
moon new consumer --user consumer_test
cd consumer
moon add mik1e80/cad_sketch
```

`--user` 用于固定消费模块名，与安装依赖所用的注册表账号无关。Windows 上若模板 README 符号链接创建失败，模板可能给出提示；下面的建模、测试与运行不依赖该链接。

保留生成模板的目录布局，替换以下五个文件：

### `moon.pkg`

```moonbit
import {
  "mik1e80/cad_sketch" @sketch,
}

import {
  "consumer_test/consumer",
} for "test"
```

### `consumer.mbt`

```moonbit
///|
pub fn edited_length() -> Double {
  let sketch = @sketch.Sketch::new()
  let a = sketch.add_point(0.0, 0.0)
  let b = sketch.add_point(3.0, 0.5)
  sketch.constrain(Fix(a, 0.0, 0.0)) |> ignore
  sketch.constrain(Horizontal(sketch.add_line(a, b))) |> ignore
  let dimension = sketch.constrain(Distance(a, b, 5.0))
  let first = sketch.solve_and_apply().unwrap()
  if !first.report.is_satisfied() ||
    (sketch.point(b).unwrap().x - 5.0).abs() > 1.0e-6 {
    abort("Initial dimension did not solve")
  }
  if !sketch.set_constraint(dimension, Distance(a, b, 7.0)) {
    abort("Dimension edit failed")
  }
  let edited = sketch.solve_and_apply().unwrap()
  if !edited.report.is_satisfied() {
    abort("Edited sketch did not solve")
  }
  sketch.point(b).unwrap().x
}

///|
pub fn rejects_invalid_radius() -> Bool {
  let sketch = @sketch.Sketch::new()
  let center = sketch.add_point(0.0, 0.0)
  let circle = sketch.add_circle(center, -1.0)
  match sketch.solve_and_apply() {
    Err(InvalidRadius(id)) => id.index == circle.index
    _ => false
  }
}
```

### `consumer_test.mbt`

```moonbit
///|
test "installed library solves an edited dimension" {
  assert_true((@consumer.edited_length() - 7.0).abs() < 1.0e-6)
}

///|
test "installed library exposes typed errors" {
  assert_true(@consumer.rejects_invalid_radius())
}
```

### `cmd/main/moon.pkg`

```moonbit
import {
  "consumer_test/consumer",
}

pkgtype(kind: "executable")
```

### `cmd/main/main.mbt`

```moonbit
///|
fn main {
  let length = @consumer.edited_length()
  if (length - 7.0).abs() > 1.0e-6 {
    abort("Wrong edited dimension")
  }
  println("Length after edit: \{length}")
}
```

然后从消费项目根目录运行：

```sh
moon info
moon fmt
moon test --target js --deny-warn
moon run cmd/main --target js --deny-warn
```

当前模板的可执行入口位于 `cmd/main`，因此运行命令显式指定这个包。`moon test` 在这里仅运行新建消费项目的两项测试：尺寸从 5 编辑到 7、类型化 `InvalidRadius` 可匹配。程序再次实际求解并检查编辑后的尺寸。

## 2026-10-22 实测

`moon new` 创建、注册表安装、两个测试和可执行程序均以零状态退出，解析版本为 `0.1.0`。在线索引刷新成功；本次安装使用标准注册表缓存。消费项目初始依赖目录为空，整个流程没有指向开发仓库的本地依赖。

```text
Total tests: 2, passed: 2, failed: 0.
Length after edit: 6.9999999993777795
```

长度目标为 7，检查容差为 `1e-6`；输出保留实际浮点结果。工具链、命令、退出码、缓存使用和示例源码 SHA-256 见[实测记录](releases/consumer-0.1.0.json)。此次没有重新发布 0.1.0，也没有重跑库的全量测试；原[发布回执](releases/0.1.0.json)保持不变。
