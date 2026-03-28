# 26-Arch 仓库快速理解

## 1. 这个仓库整体在做什么

这是复旦大学 2026 春季《计算机组成与体系结构》课程配套代码仓库（`Arch-2026-Spring-Fudan`）。它**不是**从零搭空的 RTL 练习册，而是已经搭好：

- **Verilator** 仿真与构建脚本（`verilate/`、`Makefile`）
- **差分测试 Difftest**（`difftest/`），把你的 CPU 与参考模型 `NEMU` 逐条对拍
- **预编译测试程序**（`ready-to-run/`），按 `lab1` / `lab2` / `lab3` 划分
- 后续上板所需的 **Vivado** 工程骨架（`vivado/`）

你（或课程同学）的**主线任务**是：在课程给定的接口与工程规范下，在 `vsrc/` 里实现并扩展一颗 **RISC-V** CPU，使其能通过各 Lab 的仿真测试，并在需要时完成报告与提交（`docs/report.pdf` + `make handin`）。

一句话：**在现成仿真与验证框架里，把 RISC-V CPU 从“能跑基础指令”逐步做到“能跑更完整的程序与访存能力”。**

---

## 2. Lab1 大致在推进什么能力

结合仓库里的 `Doc/Project_Overview.md`、`Makefile` 与 `ready-to-run/lab1/` 的定位，**Lab1** 侧重：

- **CPU 核主体通路**：取指、译码、执行、写回；与 **IBus** 取指、与 **Difftest** 的提交语义对齐。
- **基础整数 RISC-V 指令**：大量算术/逻辑与带 `w` 后缀的 32 位结果扩展等（具体以 `lab1-test.S` 为准）。
- 若采用**流水线**实现，会自然涉及 **数据冒险**：前递、load-use 时的阻塞等（仓库中 `core_hazard_unit.sv`、`core_forwarding_unit.sv` 即对应这类能力）。

`make test-lab1` 跑 `lab1-test.bin`；`make test-lab1-extra` 跑附加测试，通常**能力边界更高**（例如文档里提到 extra 里可能涉及乘除等类指令，需以汇编源为准）。

---

## 3. Lab2 大致在推进什么能力

`Doc/Project_Overview.md` 根据 `lab2-test.S` 归纳：**Lab2** 重点从“算对寄存器”转向 **访存**：

- **Load 系列**：如 `lb/lbu/lh/lhu/lw/lwu/ld` 等不同宽度与符号扩展。
- **Store 系列**：如 `sb/sh/sw/sd`。
- 与 **DBus** 读写、总线对齐/字节使能等语义正确配合。

`Makefile` 里 `DIFFTEST_OPTS = DELAY=0` 注释提到 “remove on lab 2”，说明 Lab2 阶段在仿真/时序上也可能与 Lab1 有工程约定差异，需要结合课程说明与 `difftest` 使用方式理解。

---

## 4. 若要读「当前 CPU 实现」，建议先看哪些文件、为什么

下面顺序适合**第一次把代码读通**，从“谁连谁、类型从哪来”到“核内部怎么拆”。

| 顺序 | 文件 | 为什么先看 |
|------|------|------------|
| 1 | `README.md` | 最短的目录地图，一眼知道 `vsrc`、仿真、测试、Makefile 各自干什么。 |
| 2 | `Makefile` | 标准命令入口：`make sim`、`make test-lab1` / `test-lab2` 等，理解验证闭环怎么被触发。 |
| 3 | `vsrc/include/common.sv` | 总线类型、`PCINIT`、与仿真一致的接口约定；**不先读它，后面信号名会对不上。** |
| 4 | `vsrc/SimTop.sv` | 仿真顶层：`core` 如何接到 **IBus/DBus**、总线转换与仲裁、内存。搞清**数据从哪来、去哪**，再进 core 不会迷路。 |
| 5 | `vsrc/src/core.sv` | **CPU 核主体**：流水线、段间寄存器、与取指/访存/写回/Trap 的连线，是阅读时间的“主战场”。 |
| 6 | 与核拆开的子模块（按需） | `core_decode.sv`（译码）、`core_alu.sv`、`core_regfile.sv`、`core_hazard_unit.sv`、`core_forwarding_unit.sv`：对应文档里 Lab1 常见的**译码 / ALU / 冒险处理**，按你关心的路径点进即可。 |
| 7 | `ready-to-run/lab1/lab1-test.S`（及 lab2 的 `lab2-test.S`） | **反推需求边界**：测试里出现哪些指令，你的实现就至少要覆盖这些语义。 |
| 8 | `difftest/doc/usage.md`（若需对接 Difftest） | 何时算“提交”、寄存器与 trap 何时对参考模型可见；流水线里尤其容易踩坑。 |

**原则**：先看 `common.sv` + `SimTop.sv` 建立**接口与系统图**，再读 `core.sv` 及子模块建立**数据通路**；用 `ready-to-run` 下的汇编**确认**当前 Lab 要你证明什么能力。

---

## 5. 小结

- **仓库整体**：课程提供的 RISC-V CPU 实验工程 = 仿真 + Difftest + 测试程序 + 你在 `vsrc/` 里写的核。
- **Lab1**：核内基础执行路径、整数指令与（若采用流水线）冒险处理；extra 往往更难。
- **Lab2**：Load/Store 与访存宽度、符号扩展、DBus 语义为主战场。
- **读代码顺序**：`README` → `Makefile` → `common.sv` → `SimTop.sv` → `core.sv`（及子模块）→ 测试汇编 →（需要时）`difftest` 文档。
