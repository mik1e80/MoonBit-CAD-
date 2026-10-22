# 生态对比与集成边界

核对日期：2026-10-22。范围为本文列出的七个相关项目，不是 MoonBit 生态的穷尽调查。依据为官方仓库 README、Moon Geometry 的 LM 公开接口与实现，以及 SolveSpace 官方技术文档；本次没有安装并运行这些对比项目，也没有测量跨库性能或收敛率。

## 本项目提供哪一层能力

`mik1e80/cad_sketch` 面向小型二维参数化草图。调用者创建点、线、圆，再用距离、方向、对称和相切等关系表达设计意图；库将关系转换为方程，联合求解坐标与半径，并返回逐约束残差和局部自由度。修改尺寸或启停关系后，可以保留草图内句柄继续求解。

因此，比较应同时看**几何对象、关系建模、参数编辑与求解诊断**。底层使用非线性最小二乘，并不意味着本项目提供了通用优化器的全部能力。这里的“保留关系”指同一进程中的 `Sketch` 对象；当前没有模型持久化，句柄不能作为跨进程标识。

## 能力与范围对照

| 项目 | 类型与已有能力 | cad_sketch 的区别 |
| --- | --- | --- |
| [MoonCurveFit](https://github.com/yyyt0807/moonbit-curvefit/blob/43d980b5429d9e5780adf7007fe7c278736104db/README.md) | 通用小型稠密非线性最小二乘；自定义残差、参数边界、稳健损失与诊断 | 提供点、线、圆和 24 种几何关系，自动构造方程，管理约束编辑与几何更新；当前未提供参数边界或稳健损失 |
| [Moon Geometry](https://github.com/walkzzz/moon-geometry/blob/375f5f87fa73b308a75969cf320c46e3de386321/README.md) | 计算几何基础类型、相交、拟合等算法，以及 [LM 优化接口](https://github.com/walkzzz/moon-geometry/blob/375f5f87fa73b308a75969cf320c46e3de386321/src/optim/levenberg_marquardt/pkg.generated.mbti) | 在几何计算与优化之外，封装草图对象、设计关系、联合求解、尺寸编辑和逐约束诊断 |
| [MoonCassowary](https://github.com/sgy1023-crt/MoonCassowary/blob/19f431f82d698173cada459ab7f35ce7dcc38ce3/README.md) | 增量线性等式 / 不等式、软约束权重与编辑变量，适用于交互布局 | 求解距离、角度、相切等非线性几何等式；每次重新线性化，当前没有增量 tableau、软约束权重或不等式 |
| [moonbit-constraint](https://github.com/mjfmjf879/moonbit-constraint/blob/932d867d9116ab6746d9f4d93df654855a6dc9cf/README.md) | 整数有限域、约束传播与搜索，包含排班和组合配置模型 | 变量为连续坐标与半径，通过局部数值迭代求解；当前没有整数有限域搜索或冲突核心证明 |
| [moonbit-step](https://github.com/gmlewis/moonbit-step/blob/3d77e2bed4bef957f7019af754bf8d2a5e772cea/README.md) | 三维建模 DSL 与 STEP 解析 / 序列化 | 聚焦二维草图关系与尺寸重求；当前没有三维实体、STEP I/O 或自动互转接口 |
| [SolveSpace](https://github.com/solvespace/solvespace/blob/30e1c3ac0beb77fe3e098315b1bb662840ddc99a/README.md) | 二维 / 三维参数化 CAD，提供几何约束求解及[独立求解库](https://solvespace.com/tech.pl) | 独立实现的小型纯 MoonBit 求解组件；未移植或链接 SolveSpace，不宣称功能或稳健性等价 |
| [dxfkit](https://github.com/mik1e80/dxfkit/blob/6d75d895c2a706c013290936f7880c1c05e88516/README.md) | ASCII DXF 读取、轮廓辅助检查与 SVG 预览 | 按设计约束修改参数化几何；当前没有 DXF 读取、轮廓检查或与 dxfkit 的自动互转接口 |

## 通用残差优化与草图关系建模

[MoonCurveFit 的接口说明](https://github.com/yyyt0807/moonbit-curvefit/blob/43d980b5429d9e5780adf7007fe7c278736104db/README.md)已包含通用残差回调、命名 `ResidualTerm`、参数边界、固定参数、缩放、稳健损失以及收敛和秩诊断。它的用途超出曲线拟合，还能承载定位、校准等领域模型。不能将其概括为“只能拟合曲线”或“没有诊断”。

从接口分工看，使用它表达 CAD 草图时，应用需要组织几何对象、将设计关系写成残差，并维护对象与诊断的对应。`cad_sketch` 的 [Constraint](../model.mbt) 和 [残差实现](../residual.mbt) 已封装 24 种关系；草图负责句柄归属、关系启停和尺寸替换，求解报告按约束返回误差。两者共享非线性最小二乘背景，本项目的主要区别在领域建模与编辑流程。

本项目目前仅处理几何等式，没有 MoonCurveFit 的参数边界或稳健损失；全部启用关系达到容差才报告成功。已有几何关系适合草图求解，自定义科学残差、观测拟合或稳健估计应另行评估通用优化接口。

## 计算几何与联合草图求解

[Moon Geometry 的项目说明](https://github.com/walkzzz/moon-geometry/blob/375f5f87fa73b308a75969cf320c46e3de386321/README.md)覆盖几何类型、相交、距离、拟合、空间结构等算法。其 [LM 接口](https://github.com/walkzzz/moon-geometry/blob/375f5f87fa73b308a75969cf320c46e3de386321/src/optim/levenberg_marquardt/pkg.generated.mbti)同时接受数值或调用者提供的解析雅可比，返回参数、残差平方和、迭代次数与成功标记；[实现](https://github.com/walkzzz/moon-geometry/blob/375f5f87fa73b308a75969cf320c46e3de386321/src/optim/levenberg_marquardt/levenberg_marquardt.mbt)也可核对。几何类型和非线性优化在生态中已经存在。

这些基础计算与本项目有重叠。本项目在其选定的草图范围内，统一管理对象、设计关系、变量布局和结果应用，例如组合 `Mirror` 与 `EqualRadius` 表达镜像孔位，再修改轴的位置继续求解。调用者直接操作几何关系，无需为每个关系提供雅可比。

这项判断基于上面列出的接口分工，不将 Moon Geometry 的全部模块简化为几个基础函数，也不据此宣称本项目在速度、精度或覆盖面上更优。当前没有直接调用 Moon Geometry 或交换其几何类型的适配层。

## 线性编辑与离散搜索

[MoonCassowary](https://github.com/sgy1023-crt/MoonCassowary/blob/19f431f82d698173cada459ab7f35ce7dcc38ce3/README.md)维护增量线性约束系统，支持等式、不等式、加权软约束、约束增删和编辑建议。它的变量也可以是连续数值；区别不在于是否支持连续变量，而在关系形式和更新方式。其布局约束适合宽度分配与最小尺寸等问题。

`cad_sketch` 处理距离、角度和相切等非线性几何等式，每次求解重新线性化；支持修改和启停关系，但尚无软约束权重、约束删除、增量 tableau 或拖拽优先级。两种编辑接口不能视为具有相同语义。

[moonbit-constraint](https://github.com/mjfmjf879/moonbit-constraint/blob/932d867d9116ab6746d9f4d93df654855a6dc9cf/README.md)以整数有限域、传播和确定性搜索组织模型，包含排班、资源分配和组合配置等应用，以及搜索诊断和冲突核心报告。本项目用 Double 坐标与半径做局部数值迭代，不提供有限域枚举或经过证明的冲突核心。`unsatisfied()` 仅列出当前结果中残差超标的关系，不能替代离散求解器的证明或搜索语义。

## CAD 应用、文件处理与求解组件

[moonbit-step](https://github.com/gmlewis/moonbit-step/blob/3d77e2bed4bef957f7019af754bf8d2a5e772cea/README.md)面向三维模型构造和 STEP 解析 / 序列化，其 README 展示建模 DSL、模型变换和文件输出。本项目的输入是二维草图对象及关系，输出是坐标、半径和诊断，不提供三维实体或 STEP 文件接口。将求解后的轮廓用于三维建模是可能的应用方向，数据映射和适配尚未实现。

[SolveSpace](https://github.com/solvespace/solvespace/blob/30e1c3ac0beb77fe3e098315b1bb662840ddc99a/README.md)是二维 / 三维参数化 CAD 工具，其[官方技术说明](https://solvespace.com/tech.pl)还明确提供可独立使用的求解库。因此区别不能写成“只有本项目可嵌入”。本项目选择较小的二维实体与关系范围，使用纯 MoonBit 独立实现，并保留当前规模与数值边界；没有复制、移植或链接 SolveSpace 代码，不声称具备等价功能、交互体验或稳健性。

[dxfkit](https://github.com/mik1e80/dxfkit/blob/6d75d895c2a706c013290936f7880c1c05e88516/README.md)侧重读取已有 ASCII DXF、分析轮廓并生成 SVG 预览。本项目侧重根据设计关系改变几何。未来可考虑把求解结果交给文件处理层，但本项目当前既不读写 DXF，也没有与 dxfkit 的自动互转接口；不应将两个仓库的能力合并计入本项目。

## 本项目贡献的代码证据

| 能力 | 仓库证据与实际边界 |
| --- | --- |
| 草图对象与关系 | [model.mbt](../model.mbt)：点、线、圆与 24 种关系；句柄包含草图归属 |
| 关系自动转方程 | [residual.mbt](../residual.mbt)、[autodiff.mbt](../autodiff.mbt)：关系残差与前向自动微分 |
| 参数编辑与重复求解 | [公开接口示例](../README.mbt.md)、[四孔安装板](SHOWCASE.md)：尺寸修改、关系启停、前后图形、独立坐标核对及失败时保留几何 |
| 机构角度驱动 | [四杆机构案例](../examples/four_bar/README.md)：同一草图的 25 个往返姿态、杆长与分支校验、轨迹图；展示运动学位置序列，未实现动力学或碰撞求解 |
| 结果诊断与应用 | [solver.mbt](../solver.mbt)：逐约束残差、局部自由度、状态；仅全部达标时应用结果 |
| 数值方法与范围 | [linalg.mbt](../linalg.mbt)、[技术说明](ARCHITECTURE.md)：阻尼 QR 和局部秩；采用稠密矩阵，无全局收敛保证 |

通用优化器也能承载几何方程，计算几何库也能用于建立设计关系。本项目将其中一组二维 CAD 使用流程封装成可直接调用的领域接口。当前上限为 256 个标量变量、512 条线和 512 条存储约束；这些输入上限不代表已测量的高性能规模。

## 来源快照与依赖关系

下列版本用于复核本文所依据的材料，不代表对方项目的最新版本承诺或运行认证：

| 项目 | 核对版本与主要材料 |
| --- | --- |
| yyyt0807/moonbit-curvefit | [43d980b5429d / README](https://github.com/yyyt0807/moonbit-curvefit/blob/43d980b5429d9e5780adf7007fe7c278736104db/README.md) |
| walkzzz/moon-geometry | [375f5f87fa73 / README](https://github.com/walkzzz/moon-geometry/blob/375f5f87fa73b308a75969cf320c46e3de386321/README.md) |
| sgy1023-crt/MoonCassowary | [19f431f82d69 / README](https://github.com/sgy1023-crt/MoonCassowary/blob/19f431f82d698173cada459ab7f35ce7dcc38ce3/README.md) |
| mjfmjf879/moonbit-constraint | [932d867d9116 / README](https://github.com/mjfmjf879/moonbit-constraint/blob/932d867d9116ab6746d9f4d93df654855a6dc9cf/README.md) |
| gmlewis/moonbit-step | [3d77e2bed4be / README](https://github.com/gmlewis/moonbit-step/blob/3d77e2bed4bef957f7019af754bf8d2a5e772cea/README.md) |
| solvespace/solvespace | [30e1c3ac0beb / README](https://github.com/solvespace/solvespace/blob/30e1c3ac0beb77fe3e098315b1bb662840ddc99a/README.md) |
| mik1e80/dxfkit | [6d75d895c2a7 / README](https://github.com/mik1e80/dxfkit/blob/6d75d895c2a706c013290936f7880c1c05e88516/README.md) |

这些项目在本文中仅用于能力比较；本项目没有新增运行时依赖、源码移植或现成集成。许可证与使用范围见 [第三方说明](../THIRD_PARTY_NOTICES.md)。未来若实际引入代码或适配层，应单独记录来源、许可、接口转换和验证结果。
