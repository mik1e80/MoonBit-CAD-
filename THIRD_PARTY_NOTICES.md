# 来源与第三方说明

本仓库的 MoonBit 实现、示例和测试由本项目编写，以 Apache-2.0 许可提供。完整许可文本见 LICENSE。当前未包含第三方 CAD 文件、二进制求解器或移植自第三方库的代码；数值部分仅调用语言自带的 MoonBit core。

## 项目、许可证与使用范围

| 项目 | 许可证与原始条款 | 本仓库使用范围 |
| --- | --- | --- |
| [MoonBit core](https://github.com/moonbitlang/core) | Apache-2.0，[LICENSE](https://github.com/moonbitlang/core/blob/main/LICENSE)；个别文件另有保留的第三方声明，以原仓库为准 | 通过工具链导入 math、debug 和基础集合；源码发布包未复制 core 的实现文件 |
| [SolveSpace](https://github.com/solvespace/solvespace) | GPLv3，[COPYING.txt](https://github.com/solvespace/solvespace/blob/master/COPYING.txt) | 阅读公开约束与技术说明，作为需求、初值和局部自由度语义参照；没有移植或链接其求解器 |
| [Ceres Solver](https://github.com/ceres-solver/ceres-solver) | BSD-3-Clause，[LICENSE](https://github.com/ceres-solver/ceres-solver/blob/master/LICENSE)；部分文件采用单独许可，以原项目标注为准 | 公开方法文档中的非线性最小二乘和自动微分背景；没有复制 Ceres 源码或测试 |
| [MoonCassowary](https://github.com/sgy1023-crt/MoonCassowary) | BSD-3-Clause，[LICENSE](https://github.com/sgy1023-crt/MoonCassowary/blob/main/LICENSE) | 仅作 MoonBit 生态范围比较；未使用其 Kiwi 移植实现、测试或生成数据 |
| [MoonCurveFit](https://github.com/yyyt0807/moonbit-curvefit/blob/43d980b5429d9e5780adf7007fe7c278736104db/README.md) | Apache-2.0，[LICENSE](https://github.com/yyyt0807/moonbit-curvefit/blob/43d980b5429d9e5780adf7007fe7c278736104db/LICENSE) | 仅作通用残差优化与草图领域接口的能力比较；未使用其源码、测试或生成数据 |
| [Moon Geometry](https://github.com/walkzzz/moon-geometry/blob/375f5f87fa73b308a75969cf320c46e3de386321/README.md) | MIT，[LICENSE](https://github.com/walkzzz/moon-geometry/blob/375f5f87fa73b308a75969cf320c46e3de386321/LICENSE) | 仅核对公开几何与 LM 接口和实现以说明范围差异；未复制、移植或调用其代码 |
| [moonbit-constraint](https://github.com/mjfmjf879/moonbit-constraint/blob/932d867d9116ab6746d9f4d93df654855a6dc9cf/README.md) | Apache-2.0，[LICENSE](https://github.com/mjfmjf879/moonbit-constraint/blob/932d867d9116ab6746d9f4d93df654855a6dc9cf/LICENSE) | 仅作有限域传播 / 搜索与连续几何迭代的能力比较；未使用其实现或数据 |
| [moonbit-step](https://github.com/gmlewis/moonbit-step/blob/3d77e2bed4bef957f7019af754bf8d2a5e772cea/README.md) | Apache-2.0，[LICENSE](https://github.com/gmlewis/moonbit-step/blob/3d77e2bed4bef957f7019af754bf8d2a5e772cea/LICENSE) | 仅作三维建模、STEP 文件处理与二维草图求解的能力比较；没有源码移植或现成集成 |
| [DXFKIT](https://github.com/mik1e80/dxfkit) | Apache-2.0，[LICENSE](https://github.com/mik1e80/dxfkit/blob/main/LICENSE) | 同一作者的独立 DXF 项目，仅作功能范围比较；未将其实现作为本项目求解器代码 |

这些许可证属于各原项目；本仓库的 Apache-2.0 不替换或覆盖它们。上表中的文档参照和比较项目不作为求解器源码的移植来源。2026-10-22 的能力对比、来源快照和集成边界见 [生态对比](docs/ECOSYSTEM.md)。

## 需求与语义参照

- [SolveSpace — Constraints](https://solvespace.com/constraints.pl)：草图约束、初值、多解和自由度的实际使用场景。
- [SolveSpace — Technology](https://solvespace.com/tech.pl)：将几何关系建模为方程、数值线性化和欠约束问题的背景。SolveSpace 使用自己的求解实现；本仓库没有复制、链接或重新许可 SolveSpace 的 GPL 代码。
- [MoonBit Cassowary](https://mooncakes.io/docs/sgy1023-crt/cassowary)：生态对比中的线性约束库，本仓库未依赖或移植它。

## 数值方法

使用通行的前向自动微分链式法则、阻尼 Gauss–Newton、列缩放、Givens 旋转 QR 和完全选主元消元法。实现根据数学公式编写。方法背景可参见：

- [Ceres Solver — Non-linear Least Squares](https://ceres-solver.org/nnls_solving.html)：阻尼、信赖域及稠密 QR 的方法背景；本项目不是 Ceres 的移植，也没有实现其完整信赖域策略。
- [Ceres Solver — Automatic Derivatives](https://ceres-solver.org/automatic_derivatives.html)：前向自动微分与链式法则背景；本仓库使用自行实现的稠密导数数组。

测试的几何期望值来自解析几何：勾股定理、三角函数、直线法向距离和两圆交点公式。自动微分与独立中心差分逐分量比较。没有将其他项目的测试语料重新标为本项目作品。

## 生成文件、示例与开发工具

`pkg.generated.mbti` 由 MoonBit 的 `moon info` 根据本仓库接口生成；示例、解析期望值和测试数据由本项目构造。构建产物、依赖缓存和 Git 内部文件不进入源码发布包，`scripts/check_package.py` 会检查实际压缩包。

GitHub Actions 使用的 `actions/checkout` 和 `actions/setup-python` 为 MIT 许可的 CI 工具，分别见[checkout LICENSE](https://github.com/actions/checkout/blob/main/LICENSE)和[setup-python LICENSE](https://github.com/actions/setup-python/blob/main/LICENSE)；只在工作流中引用，不复制其实现。Python 审查脚本只使用标准库，是开发验证工具，不参与 MoonBit 库的运行时。
