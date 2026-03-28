# 项目总览与实施路径

本文档用于固化对本仓库及课程实验的整体理解，目标是帮助后续阅读代码、定位实现入口、规划 Lab 推进路径。

---

## 1. 项目定位

该仓库不是一个从零开始搭建的 CPU 空白工程，而是课程已经提供了：

- 仿真框架
- 差分测试框架（Difftest）
- 预编译测试程序
- Verilator 构建脚本
- 后续上板所需的 Vivado 工程骨架

学生的主要任务是在既有框架下逐步实现一个基于 RISC-V 的 CPU，并在各 Lab 中按阶段扩展能力，最终做到：

- 能在仿真环境中正确执行测试程序
- 能与参考实现进行逐条指令差分验证
- 能形成可提交的实验结果与报告
- 在后续阶段具备继续上板的工程基础

从仓库现状看，当前最核心的实现位置是 `vsrc/src/core.sv`。

---

## 2. 项目总体目标

结合仓库结构、测试程序和课程说明，可以将本项目的总体目标概括为以下几层：

### 2.1 功能目标

逐步实现一个支持 RISC-V 指令执行的 CPU。

初期重点是：

- 基础整数运算
- 正确取指、译码、执行、写回
- 与仿真总线正确交互
- 在 Difftest 中正确提交指令与体系结构状态

随后逐步扩展到：

- Load/Store 访存支持
- 更多控制流指令
- 更真实程序的运行能力
- 上板运行所需的工程整合

### 2.2 工程目标

不仅要“写出能跑的逻辑”，还要遵守课程提供的工程组织方式：

- 在指定目录中实现 CPU
- 使用统一 `Makefile` 完成构建与测试
- 通过 Difftest 与 NEMU 对拍
- 按要求生成报告与提交压缩包

### 2.3 学习目标

该项目本质上对应的是“从体系结构知识走向可运行硬件实现”的训练过程，重点覆盖：

- RISC-V 指令格式与执行语义
- 流水线 CPU 的组织方式
- 冒险、阻塞、前递等基本处理思路
- 仿真、调试、验证和工程交付流程

---

## 3. 仓库结构与职责划分

仓库根目录中与实验最相关的内容如下：

```text
26-Arch/
├── build/         # 仿真生成目录
├── difftest/      # 差分测试框架
├── ready-to-run/  # 预编译测试程序
├── verilate/      # Verilator 构建与仿真规则
├── vivado/        # 上板相关工程
├── vsrc/          # CPU 代码主体
├── Doc/           # 实验说明与整理文档
├── docs/          # 提交报告目录
├── Makefile       # 构建、测试、提交入口
└── README.md
```

### 3.1 `vsrc/`

这是最核心的开发目录。

- `vsrc/src/core.sv`：CPU 核主体，后续实现分析的第一入口
- `vsrc/include/common.sv`：公共类型、总线接口、`PCINIT` 等关键定义
- `vsrc/include/config.sv`：配置参数
- `vsrc/SimTop.sv`：仿真顶层，把 `core` 接到总线、RAM 和 Difftest 环境
- `vsrc/util/`：总线转换与仲裁逻辑，通常由框架提供，不是当前 Lab 的主要改动点

### 3.2 `ready-to-run/`

该目录存放按 Lab 划分的测试程序。

- `lab1/`：Lab1 基础测试与附加测试
- `lab2/`：Lab2 测试
- `lab3/`：Lab3 及扩展测试

其中 `.S` 文件可以帮助理解测试覆盖的指令类别和能力边界，`.bin` 文件被仿真器直接加载。

### 3.3 `difftest/`

这是课程提供的差分测试框架，用于把你的 CPU 与参考实现 NEMU 做逐指令比对。

其主要职责是：

- 接收 CPU 的提交信息
- 接收体系结构寄存器/CSR 状态
- 使用参考模型进行行为对拍
- 在出现偏差时帮助定位错误

通常不应修改该目录内部实现。

### 3.4 `verilate/`

用于组织 Verilator 仿真流程，负责把 SystemVerilog 工程编译为 C++ 仿真程序。

一般情况下不需要修改该目录，只需理解它是仿真链路的一部分。

### 3.5 `vivado/`

这是后续上板相关路径，与 Verilator 仿真路径相对独立。

当前观察到的内容表明：

- 仓库为 Basys3 板卡准备了工程和约束
- `mycpu_top.sv` / `VTop.sv` 更贴近综合与板级连接
- `SimTop.sv` 更偏仿真顶层

因此后续阅读时需要区分“仿真顶层”和“综合/上板顶层”。

### 3.6 `Doc/` 与 `docs/`

二者用途不同：

- `Doc/`：课程说明、笔记、阶段性文档
- `docs/`：提交用目录，其中需要放 `report.pdf`

---

## 4. 项目的运行链路

从工程角度看，这个仓库的主线不是“直接运行 Verilog”，而是：

```text
make test-lab1
    ↓
make sim
    ↓
编译 core.sv + SimTop.sv + difftest
    ↓
生成 build/emu
    ↓
加载 ready-to-run/lab1/lab1-test.bin
    ↓
CPU 通过 IBus/DBus 与仿真内存交互
    ↓
Difftest 将 CPU 执行结果与 NEMU 对拍
    ↓
输出 HIT GOOD TRAP 表示通过
```

对应的几个关键点如下：

### 4.1 构建入口

常用命令：

- `make init`：初始化子模块
- `make sim`：编译仿真
- `make test-lab1`：运行 Lab1 基础测试
- `make test-lab1-extra`：运行 Lab1 附加测试
- `make test-lab2`：运行 Lab2 测试
- `make test-lab3`：运行 Lab3 测试
- `make handin`：打包提交文件

### 4.2 成功标志

根据课程说明与仿真代码：

- 仿真正确时会出现 `HIT GOOD TRAP`
- 该字符串不一定出现在最后一行，需要在输出中查找

### 4.3 提交方式

提交依赖 `make handin`，前提是存在：

- `docs/report.pdf`

然后脚本会要求输入：

- 学号-姓名
- Lab 编号

最后生成提交压缩包。

---

## 5. Lab 的能力演进判断

结合测试汇编内容，可以大致推断各 Lab 的重点能力演进如下。

### 5.1 Lab1

Lab1 更像 CPU 主体能力的起点，当前能明确看到：

- 基础整数指令测试
- 大量逻辑/算术类操作
- `w` 结尾的 32 位结果扩展类操作

此外：

- `lab1-extra-test.S` 中已出现 `mul/div/rem` 等乘除模相关指令
- 因此 Lab1 附加测试的能力边界高于基础测试

这说明 Lab1 至少覆盖：

- 指令译码
- ALU 运算
- 结果写回
- 提交语义与 Difftest 基本对齐

如果采用流水线实现，则数据相关问题也会较快出现。

### 5.2 Lab2

`lab2-test.S` 中已明确包含：

- `lb/lbu/lh/lhu/lw/lwu/ld`
- `sb/sh/sw/sd`

因此可以判断 Lab2 的重点明显转向：

- 访存指令支持
- 不同访存宽度与符号扩展
- 总线读写语义

### 5.3 Lab3

`lab3-test.S` 已明显接近真实程序执行场景，包含：

- `auipc`
- `beq/bltu`
- `jal`
- 栈相关读写
- 更长控制流和函数调用

这意味着 Lab3 对 CPU 的要求已经不只是“执行单条指令”，而是要具备更完整的程序运行能力。

---

## 6. 当前阶段最关键的实现焦点

如果当前目标是理解和推进 Lab1，那么最值得关注的是以下几点。

### 6.1 主战场是 `core.sv`

当前仓库里的 `vsrc/src/core.sv` 仍然是空壳，说明课程期望学生在此处完成 CPU 核心实现。

该文件中已经预留了：

- IBus 接口
- DBus 接口
- 中断相关输入
- Difftest 相关模块实例

但 Difftest 的输入目前仍是占位值，因此真正可用的提交逻辑还需要和 CPU 实现一起补齐。

### 6.2 需要遵守 `common.sv` 的接口定义

`vsrc/include/common.sv` 中定义了关键接口和常量，例如：

- `PCINIT`
- `ibus_req_t` / `ibus_resp_t`
- `dbus_req_t` / `dbus_resp_t`
- 总线宽度与类型定义

后续实现必须围绕这些类型组织，而不是随意自定义顶层接口。

### 6.3 `SimTop.sv` 是理解信号流向的关键中间层

`SimTop.sv` 说明了：

- `core` 如何接入 IBus/DBus
- IBus/DBus 如何转成统一总线
- 总线如何仲裁
- RAM 与中断信号如何连接

因此若后续出现“为什么仿真跑不起来”“取指/访存没有返回”的问题，`SimTop.sv` 是必须先看懂的桥梁文件。

### 6.4 Difftest 的核心原则必须尽早理解

根据 `difftest/doc/usage.md`，最关键的原则是：

> 在指令提交的时刻，其产生的体系结构影响恰好生效。

这意味着后续在连接：

- `DifftestInstrCommit`
- `DifftestArchIntRegState`
- `DifftestTrapEvent`
- `DifftestCSRState`

时，需要非常注意：

- 指令提交时刻
- 寄存器堆写回何时对外可见
- 某些信号是否要延后一拍再送给 Difftest

这个问题在流水线 CPU 中尤其关键。

---

## 7. 建议的实施路径

从后续学习和实现效率看，建议按下面顺序推进。

### 7.1 第一步：先建立全局地图

优先读以下文件，理解工程角色分工：

- `README.md`
- `Makefile`
- `Doc/Prepare/Dir.md`
- `vsrc/include/common.sv`
- `vsrc/SimTop.sv`

目标不是立刻写代码，而是先清楚：

- 代码该写在哪里
- 测试怎么跑
- 接口怎么接
- 仿真链路如何形成闭环

### 7.2 第二步：聚焦 `core.sv`

后续深入时应优先分析：

- 处理器内部组织方式
- 状态寄存器与数据通路
- 是否采用单周期、多周期或流水线
- 提交点和写回点定义

如果已经开始实现 Lab1，这一步也最适合做逐模块复盘。

### 7.3 第三步：用测试程序反推需求边界

建议结合以下文件：

- `ready-to-run/lab1/lab1-test.S`
- `ready-to-run/lab1/lab1-extra-test.S`

从测试出现的指令反推：

- 基础测试最低要求是什么
- 附加测试多覆盖了哪些能力
- 当前实现缺口可能落在哪些指令或语义上

### 7.4 第四步：再看 Difftest 对接

在 CPU 基本执行路径清楚后，再集中分析：

- 何时算“提交”
- 如何向 Difftest 报告提交信息
- 寄存器堆快照何时采样
- Trap/CSR 等信号何时生效

这样更容易把“功能正确”和“验证正确”区分开来。

---

## 8. 后续深入阅读的建议入口

当需要继续深入“当前项目内容”或“已有 Lab1 实现”时，建议按下面顺序展开：

1. `vsrc/src/core.sv`
2. `vsrc/include/common.sv`
3. `vsrc/SimTop.sv`
4. `ready-to-run/lab1/lab1-test.S`
5. `ready-to-run/lab1/lab1-extra-test.S`
6. `difftest/doc/usage.md`

如果要从工程外层往内层理解，也可以采用另一条顺序：

1. `Makefile`
2. `SimTop.sv`
3. `core.sv`
4. `common.sv`
5. 测试汇编
6. Difftest 文档

---

## 9. 当前观察到的注意事项

在阅读现有文档时，有几点需要特别说明：

- `Doc/Lab1/Overall.md` 与 `Doc/Lab1/Phase1.md` 更像整理后的说明材料，可作为参考，但不应替代对仓库实际结构和测试链路的核对
- `Phase1.md` 中提到的 `skill.sh`，当前仓库内未找到对应文件，因此应以实际存在的 `Makefile`、`vsrc/` 和 `difftest/` 结构为准
- 当前 `docs/report.pdf` 已存在，说明提交材料目录已被使用，但这不影响后续对 CPU 实现本身的分析

---

## 10. 小结

本项目的核心不是单独写几条 Verilog 逻辑，而是在课程给定框架中逐步做出一个可验证、可测试、可扩展的 RISC-V CPU 工程。

对当前阶段而言，最重要的理解是：

- 代码主体在 `vsrc/src/core.sv`
- 验证主线依赖 `SimTop + Difftest + ready-to-run`
- `Makefile` 决定了项目的标准运行方式
- Lab 是逐层扩展能力，而不是一次性完成所有特性

因此，后续无论是阅读已有实现，还是定位 Lab1 的问题，都应先围绕 `core.sv`、`SimTop.sv`、`common.sv` 和测试程序建立清晰映射，再进入具体细节。
