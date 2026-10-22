# Mooncakes 发布与独立安装验证

模块：`mik1e80/cad_sketch`；当前版本：`0.2.1`（首版 `0.1.0` 保留不可变）。[Mooncakes 包页面](https://mooncakes.io/docs/mik1e80/cad_sketch)。

## 使用方安装

在已有 MoonBit 项目的根目录运行：

```sh
moon add mik1e80/cad_sketch
```

使用方的 `moon.pkg`：

```moonbit
import {
  "mik1e80/cad_sketch" @sketch,
}
```

继续阅读[快速开始](QUICK_START.md)。开发时可用本地 workspace；注册表安装验证使用独立项目，不通过 workspace 或本地路径替换依赖。

## 维护者发布

按 [MoonBit 官方发布说明](https://docs.moonbitlang.com/en/stable/toolchain/moon/package-manage-tour.html)操作。使用兼容工具链，确认 `moon.mod` 的模块名、版本、许可证、仓库和 README。版本变更后重新检查归档内容，避免上传未准备好的版本。

```sh
moon login
moon package --list
moon publish --dry-run
moon publish
```

`moon login` 将凭据保存在本机工具链目录，不应复制到仓库。`moon package` 只创建本地 ZIP；只有服务端确认正式发布成功，才能视为已经上传。预检不发布版本。当前验证工具链对成功预检返回的 `202 Accepted` 仍可能以非零退出，须核对服务端明确的 “Dry run completed successfully. No changes were made” 信息；不能把任意非零退出当成成功。

归档包括核心 MoonBit 源码、文档和示例；可选的 `dev/scipy/` 工具通过 `.moonignore` 排除。没有新增运行时依赖。不要向已发布的版本重复上传修改内容；需更新时递增版本。

## 轻量验证范围

首版交付检查发布包及其解包后的静态编译、6 项 README 公开接口示例，以及注册表独立项目的尺寸编辑和类型化错误处理。独立项目必须通过 `moon add` 获取 `0.1.0`，不含 `moon.work`、path 依赖或本地源码替换。

本次不重跑全量回归、后端矩阵、400 / 1000 项实验或 SciPy 对照。历史数据保留其原始源码指纹；提交使用 `[skip ci]` 跳过自动全量工作流。Mooncakes 发布不等于 GitHub Release，也不表示赛事验收已完成。


## 0.1.0 实际发布记录

2026-10-22，正式上传返回 `200 OK`。随后在不属于本地 workspace 的独立项目执行 `moon add mik1e80/cad_sketch`，解析并下载 `0.1.0`；JS 下两项冒烟检查均通过：尺寸 5→7 的求解与编辑、公开 `SketchError::InvalidRadius` 模式匹配。已下载的 99 个归档文件逐字节与上传包一致。

[发布回执](releases/0.1.0.json)记录归档 SHA-256、工具链和验证范围。回执在发布后生成，不属于不可变的 0.1.0 归档。此次未创建 GitHub Release；源码和安装文档通过 Git 提交同步。


## 完整 Consumer Test

发布后的独立安装检查进一步补齐 `moon new → moon add → 最小示例 → moon test → moon run` 全流程；仓库外新项目的两个测试及可执行程序均通过。运行 `python scripts/check_consumer.py` 可复现，完整手工步骤、代码、缓存说明与真实结果见 [Consumer Test](CONSUMER_TEST.md)。该检查只使用公开发布的 0.1.0，未再次发布版本，也不执行库的全量回归。


## 仓库名称与已发布版本

GitHub 源码仓库使用 [mik1e80/moonbit-cad-sketch](https://github.com/mik1e80/moonbit-cad-sketch)，README 标题为 MoonBit CAD Sketch，Mooncakes 模块名继续为 `mik1e80/cad_sketch`。`moon.mod` 的 `repository`、克隆示例和源码文档链接均使用新地址。已有本地检出可执行：

```sh
git remote set-url origin https://github.com/mik1e80/moonbit-cad-sketch.git
```

已发布的 0.1.0 归档包含发布时的原仓库地址，归档保持不可变；本次重命名不重新发布该版本，也不修改原发布回执、源码指纹或历史测量。新地址随后续版本元数据发布。


## 0.2.0 版本与验证策略

0.2.0 将 `Sketch::to_svg()`、`SvgOptions` 和 `SvgBounds` 纳入正式包，模块元数据使用重命名后的仓库地址。0.1.0 归档及历史回执保持不变。

默认 Actions 只运行四后端静态编译、7 项 README 与 9 项 SVG 测试，JS 另运行 5 项真实源码归档消费测试。工作流中的 `full` job 只有在手动触发并勾选 `full_regression` 时才运行；日常提交和默认手动触发不会执行全量回归、400 / 1000 模型实验或完整包矩阵。提交使用 `[skip ci]` 时，可在同一提交上手动触发默认冒烟检查。

`python scripts/check_package.py` 默认只执行消费包的 5 项 JS 测试，使用 `--package audit/cad_consumer`，避免 workspace 把库测试连带执行。`--full` 为明确的完整检查入口。`python scripts/check_consumer.py --archive <上传ZIP>` 在仓库外安装当前版本，执行 3 项 JS 测试与可执行程序，并独立解析 SVG、逐字节核对归档。

GitHub 对应交付名称为 `v0.2.1`。发布记录分别保存 Mooncakes 的实际服务端结果、消费检查和对应提交的 Actions 结果，历史规模数据不改写为本版的新测量。

0.2.1 修复开发消费工具对多行 SVG 的解析；核心库与 0.2.0 相同。0.2.0 的安装、三项测试及程序运行已通过，工具末尾的 XML 解析问题在 0.2.1 修复。


## 0.2.1 实际发布与消费记录

2026-10-22 正式发布返回 `200 OK`。仓库外全新项目从注册表下载 0.2.1，未命中缓存；110 个上传归档文件与安装文件逐字节一致。尺寸编辑、类型化错误及 SVG 接口的 3 项 JS 测试通过，程序实际输出尺寸 6.9999999993777795，多行 SVG 经独立 XML 解析通过。

[发布回执](releases/0.2.1.json)和[消费记录](releases/consumer-0.2.1.json)保留真实版本、归档指纹与验证范围。GitHub 正式版本入口为 [v0.2.1](https://github.com/mik1e80/moonbit-cad-sketch/releases/tag/v0.2.1)，发布验证附件记录对应提交和四后端冒烟工作流结果。

旧包检查脚本首次执行曾意外连带运行 112 项 JS 测试，全部通过；已修复默认执行范围为消费模块的 5 项测试。首次交付至本次例外授权前未再执行库全量回归；随后对当前 Release 的完整回归结果见下节，SciPy 对照与四档 Benchmark 计时仍未重测。


## 2026-10-22 当前 Release 完整回归

2026-10-22，按用户本次例外授权，对 **`v0.2.1` / `458d5f397b2112e392b859c5a3054fafa1eb9185`** 执行完整回归，[实际工作流](https://github.com/mik1e80/moonbit-cad-sketch/actions/runs/39787171206)结果为 **success**。

| 检查 | 实际结果 |
| --- | --- |
| wasm / wasm-gc / JS / native 全量测试 | 各 107/107 通过 |
| 六组自动模型配置 | 四后端各 400/400，通过每后端 6 项检查器故障注入 |
| JS 随机三角形初值 | 1000/1000 Satisfied；Stalled / IterationLimit / Invalid 均为 0 |
| 解包后的完整测试与消费检查 | 四后端各 112/112（107 项库测试 + 5 项消费测试） |
| 安装板、四杆机构、编辑与冲突示例 | 通过 |
| Benchmark | Small 冒烟通过；四档性能计时未重测 |

完整摘要：[full-regression.json](releases/0.2.1-full-regression.json)；[逐模型原始数据 ZIP](https://github.com/mik1e80/moonbit-cad-sketch/releases/download/v0.2.1/full-regression-results.zip)；[完整任务日志](https://github.com/mik1e80/moonbit-cad-sketch/releases/download/v0.2.1/full-regression.log)。ZIP 的 SHA-256 为 `239725cd4cb3d3a92f4aa57bcad1cd06618a2ff9a16cffbcb6d197ab3be759c3`，已与 GitHub artifact 摘要核对一致。

原 `verification.json` 保留首次发布时的轻量验证记录，本节是随后补充的全量结果。旧批量快照保持原始指纹，新运行证据单独保存；SciPy 开发对照及四档 Benchmark 未重测。日常 CI 仍默认轻量，未修改 tag、运行时代码或已发布的 Mooncakes 包。
