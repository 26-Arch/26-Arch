# RISC\-V 流水线 CPU Lab1 指南

## Turn 1

### 🤖 Assistant

这份针对 Lab1 Phase 1 的 `lab1_phase1_skeleton_1c8b9f86.plan.md` 计划是一份质量非常高的实现蓝图，准确抓住了五级流水线设计的核心矛盾和 Verilog 硬件描述的红线。
以下是对该计划的详细评估以及需要在后续实现中额外注意的“避坑”建议：

---

### ⚠️ 需要微调与重点关注的细节 (Watch-outs)
虽然框架很棒，但在落实到具体代码时，以下几个细节很容易引发隐蔽的 Bug：
**1. Difftest 的 valid 信号定义需要修正**

- **计划中的隐患**：计划中提到 `valid = WB 有效（如 reg_write_wb | mem_read_wb 等）`。
- **修正建议**：并非所有有效指令都会写寄存器或读写内存（例如分支指令 `BEQ`、`BNE`，或者纯粹的空指令 `NOP`）。如果仅用 `reg_write` 等信号判断，遇到分支指令时 Difftest 将不会触发比对，导致指令丢失。
- **正确做法**：从 IF 阶段开始，为每条取出的合法指令生成一个全局的 `inst_valid` 信号。这个信号伴随 `instr` 和 `pc` 一起穿过 4 个段间寄存器，到达 WB 阶段。只要到达 WB 阶段的 `inst_valid` 为 `1`（且不是因为冒险插入的 Bubble 气泡），就代表有一条指令真实完成了，此时令 `DifftestInstrCommit.valid = inst_valid`。
**2. 寄存器状态比对（DifftestArchIntRegState）的时序陷阱**

- **计划中的隐患**：计划提出直接“接寄存器堆读出”给 Difftest。
- **修正建议**：Difftest 通常在时钟沿检测状态。如果在同一个时钟上升沿，WB 阶段的指令向 RegFile 写入了新数据，而 Difftest 也在同一个时钟沿去读取 RegFile 送去比对，此时它读到的可能是**写入前的旧数据**。
- **正确做法**：可以通过旁路逻辑（Bypass）解决。在给 Difftest 传递寄存器状态时，如果发现正在访问的寄存器编号刚好等于当前 WB 阶段正在写的寄存器编号（且不是 `x0`），则直接将 WB 阶段的 `wdata` 转发给 Difftest 接口，而不是给它 RegFile 里还没更新的值。
**3. wdest 信号的位宽对齐**

- 实验指南 Wiki 中曾特别提醒：`wdest` 信号是 8 位的。由于 RV32/64I 的通用寄存器只有 32 个（占 5 位），在接入 `DifftestInstrCommit` 时，记得将其补齐，例如使用拼接语法 `.wdest({3'b0, rd_wb})`。
**总结**：
可以直接按照这个 `.plan.md` 的路线开工。由于今天是 Lab1 的 DDL，建议把精力集中在把各个模块按照计划例化连线上，跑通基础流水线后再立即去处理 Data Hazard（数据冒险）的前递（Forwarding）逻辑。
