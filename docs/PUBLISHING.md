# Mooncakes 发布与独立安装验证

模块：`mik1e80/cad_sketch`；首个发布版本：`0.1.0`。[Mooncakes 包页面](https://mooncakes.io/docs/mik1e80/cad_sketch)。

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
