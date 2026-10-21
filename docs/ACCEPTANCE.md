# 验收前核对记录

核对日期：2026-10-16。本文件记录代码证据与待完成事项，不表示组委会已批准项目。

## 对照来源

- 用户提供的[九月公告](https://mp.weixin.qq.com/s/RIDBUJ0O3_PR-xUxgsG6wg)，正文及海报指向黑客松官网。
- [官方当前活动页](https://moonbitlang.github.io/Hackathon2026/)：十月赛季、最多提交 3 次、公开连续开发、可运行与可解释等要求。
- 官网链接的[正式章程](https://bxup9uklfcb.feishu.cn/wiki/Dx4Bwd6D1i3GfHkajQCcF7SznEd)：第 5.1 节项目验收、第 7 节开源与成果提交要求；读取时页面显示 10 月 10 日修改。

两个官方页面的日期信息不一致：活动首页写十月报名和验收截至 10 月 31 日，章程时间表仍写 10 月 24 日，部分章节还保留九月日期。应向组委会确认适用赛程，准备工作宜按较早时间完成。本文不将其中任一日期当成已消除歧义的最终口径。

## 仓库内证据

| 要求 | 本仓库证据与边界 |
| --- | --- |
| MoonBit 为主要实现语言 | 求解、自动微分、线性代数、验证和示例均为 MoonBit；Python 只做发布包及消费方验证，不参与求解运行时 |
| 源码公开，保留开发记录 | [GitHub 仓库](https://github.com/mik1e80/MoonBit-CAD-)；使用 `git log --oneline`、`git rev-list --count HEAD` 复核历史，已保留首版及逐项完善提交；满足用户至少 10 条 commit 的要求，不伪造开发日期 |
| 完成声明的核心功能 | 24 种小型二维草图关系；输入、数值及规模边界见 README，不声称完整 CAD、全局收敛、精确刚性判定或 DXF 集成 |
| 安装、使用、示例可复现 | README 与可执行 README.mbt.md，`cmd/demo`、`cmd/edit_demo`；尚未发布时按本地 workspace 消费源码 |
| CI 覆盖检查、构建、测试 | `.github/workflows/ci.yml` 执行格式、全目标零警告检查、构建、四后端测试、示例及发布包消费验证；验收时需以最新提交的实际 Actions 结果为准 |
| 核心路径测试 | AD 差分、解析几何、机构运动、矛盾 / 冗余、启停、极端数值、跨草图误用、资源边界；已有失败反例先复现再修复 |
| 开源和参考来源 | 完整 Apache-2.0 LICENSE；THIRD_PARTY_NOTICES.md 记录参考项目名称、链接、许可证和具体范围；没有第三方 CAD 样例或求解器代码进入源码包 |
| AI 使用可解释 | docs/ARCHITECTURE.md 说明建模、数值步骤、质量边界及 AI 协作；参赛者仍需掌握并解释这些内容 |
| Mooncakes 发布 | **待完成。正式章程第 5.1 节要求发布到 mooncakes.io；`moon package` 仅生成本地压缩包，不等同于发布** |

## 本次重点修复

1. 跨草图同号句柄曾被错误视为有效对象，可能误读、误改或关联错误几何。现通过草图身份标识校验查询、编辑、关系、结果与报告。
2. 世界坐标经过再次归一化时，容差边缘可能掩盖真实超标。现直接以返回坐标计算全部最终残差，并改进点线距离的数值稳定性。
3. 参考来源说明补全许可证名称、原始许可链接和参考范围，区分实际核心依赖与需求 / 方法 / 生态比较来源。
4. 新增 `Mirror(a,b,axis)` 直线轴对称关系；与中心对称分开说明。24 组旋转、平移、缩放及反向轴的解析反射对照，另测轴上重合、自镜像、非法归属和冲突回退。
5. `cmd/mirror_demo` 提供镜像孔位与移动对称轴的完整使用流程，在 wasm 和 JS 的 CI 中执行；实际源码包的独立消费方另验证公开 Mirror 接口。

## 可复现命令

需要 MoonBit 0.10.15 或更新版本；包消费审查脚本另外需要 Python 3.10+，仅使用标准库。

```sh
moon fmt --check
moon check --target all --deny-warn
moon build
moon test --target wasm
moon test --target wasm-gc
moon test --target js
moon test --target native
moon run cmd/demo
moon run cmd/edit_demo
moon run cmd/edit_demo --target js
moon run cmd/mirror_demo
moon run cmd/mirror_demo --target js
python scripts/check_package.py
git log --oneline
git rev-list --count HEAD
```

## 提交验收前仍需完成

- 授权并完成 Mooncakes 发布，确认包可安装、文档可读，登记包页面链接，再同步更新 README 中“尚未发布”的状态。
- 由参赛者确认本期报名成功、个人 / 组队信息、已使用的提交次数、赛事群 GitHub 昵称及适用截止时间。仓库与 CI 无法证明这些账户和报名事项。
- 参赛者实际运行示例并熟悉技术说明，能说明与 Cassowary、SolveSpace 和 DXFKIT 的范围差异，以及未收敛和局部自由度的含义。

发布前不能将本表描述为“全部验收项已满足”。最终认定由赛事组完成。

## 2026-10-22 参数化安装板案例

新增 [四孔安装板 Showcase](SHOWCASE.md) 与 `cmd/bracket_demo`。同一草图依次完成板宽 120→160、孔半径 5→8、水平孔心边距 20→30，输出真实坐标、原约束编号和逐约束诊断。构造轴由板边中点决定，四孔通过镜像、等半径和点线距离关系求解；编辑函数不直接设置目标坐标。

`node scripts/bracket_showcase.cjs --check` 独立核对四个角点、四个构造轴端点、四个孔心及四个半径，并检查已提交 SVG 与实际输出一致。额外启用宽度 170，验证未达标时全部 28 个几何数值不变；关闭冲突后恢复。JSON 中保存几何与候选报告的区别见案例说明。

新增测试覆盖另一组板宽、板高、半径和双向边距变化。wasm、wasm-gc、JS 与 native 上各 65 项测试通过；Showcase 另在 wasm 与 JS 上做独立脚本检查。CI 加入这两个检查，实际源码包验证也要求包含案例、说明、SVG 和脚本，并从解包目录运行示例与图形检查。

该案例完成参数化零件展示与复现验证，不表示 Mooncakes 发布、赛事账户事项、批量稳定性统计或 Benchmark 已完成。
