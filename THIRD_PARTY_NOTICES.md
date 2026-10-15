# 来源与第三方说明

本仓库的 MoonBit 实现、示例和测试由本项目编写，以 Apache-2.0 许可提供。完整许可文本见 LICENSE。当前未包含第三方 CAD 文件、二进制求解器或移植自第三方库的代码；数值部分仅调用语言自带的 MoonBit core。

## 需求与语义参照

- [SolveSpace — Constraints](https://solvespace.com/constraints.pl)：草图约束、初值、多解和自由度的实际使用场景。
- [SolveSpace — Technology](https://solvespace.com/tech.pl)：将几何关系建模为方程、数值线性化和欠约束问题的背景。SolveSpace 使用自己的求解实现；本仓库没有复制、链接或重新许可 SolveSpace 的 GPL 代码。
- [MoonBit Cassowary](https://mooncakes.io/docs/sgy1023-crt/cassowary)：生态对比中的线性约束库，本仓库未依赖或移植它。

## 数值方法

使用通行的前向自动微分链式法则、阻尼 Gauss–Newton、列缩放、Givens 旋转 QR 和完全选主元消元法。实现根据数学公式编写。方法背景可参见：

- [Ceres Solver — Non-linear Least Squares](https://ceres-solver.org/nnls_solving.html)：阻尼、信赖域及稠密 QR 的方法背景；本项目不是 Ceres 的移植，也没有实现其完整信赖域策略。
- [Ceres Solver — Automatic Derivatives](https://ceres-solver.org/automatic_derivatives.html)：前向自动微分与链式法则背景；本仓库使用自行实现的稠密导数数组。

测试的几何期望值来自解析几何：勾股定理、三角函数、直线法向距离和两圆交点公式。自动微分与独立中心差分逐分量比较。没有将其他项目的测试语料重新标为本项目作品。
