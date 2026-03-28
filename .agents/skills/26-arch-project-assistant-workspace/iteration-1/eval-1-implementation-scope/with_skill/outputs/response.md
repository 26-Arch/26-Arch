# 当前实现支持到哪一阶段（Lab1 / Lab1-extra / Lab2）

**一句话结论：** 与仓库标准 Difftest 流程对照，当前 RTL 已达到 **Lab1 基础测试可跑通**；**Lab1-extra** 与 **Lab2** 在**实际仿真中均未通过**，且与**代码结构**、**测试程序边界**一致——并非“仅有测试失败、实现其实已齐”的情况。

---

## 1. 依据来源说明

| 维度 | 本回答如何用 |
|------|----------------|
| **代码结构** | 查看 `vsrc/src/core_decode.sv`、`vsrc/src/core.sv`、`vsrc/include/common.sv` 中译码、ALU、PC、数据总线请求是否真实实现。 |
| **测试边界** | 对照 `ready-to-run/lab1/lab1-extra-test.S` 与 `ready-to-run/lab2/lab2-test.S` 的反汇编片段，看首条及典型指令类别是否与实现匹配。 |
| **实际测试结果** | 使用与 `Makefile` 一致的 `make test-lab1` 及同参数 `emu` 运行 `lab1-extra-test.bin`、`lab2-test.bin`（见下文命令与关键输出）。 |

---

## 2. Lab1 基础：状态为「已对齐标准验证」

### 实际测试

- **命令：** `make test-lab1`（会先 `make sim` 再运行 `./build/emu --diff … -i ./ready-to-run/lab1/lab1-test.bin`）。
- **结果：** **通过**。
- **关键成功行：** `Core 0: HIT GOOD TRAP at pc = 0x80010004`，`instrCnt = 16,385`。

说明：在 NEMU 参考模型对比下，Lab1 基线二进制能执行到约定 trap，Difftest 提交路径与寄存器状态对当前程序集是一致的。

### 代码与测试边界（与通过结论一致）

- `core_decode.sv` 对 **R-type / I-type ALU** 子集（如 `add`/`sub`、`addi`、逻辑运算、`addw`/`subw` 等）有明确 `reg_write` 与 `alu_op` 赋值。
- `core.sv` 中 PC 为顺序 `pc+4`，与 Lab1 测试以算术/逻辑为主、无分支跳转的用法相容；`lab1-test.S` 反汇编中可见大量 `add`/`subw`/`addi`/`andi`/`xori`/`addiw` 等，落在当前译码覆盖范围内。

---

## 3. Lab1-extra：状态为「未通过标准测试；实现与 M 扩展强测不匹配」

### 实际测试

- **命令：** `./build/emu --diff ./ready-to-run/riscv64-nemu-interpreter-so -i ./ready-to-run/lab1/lab1-extra-test.bin`（与 `make test-lab1-extra` 运行时一致，仅省略重建以复用已构建的 `emu`）。
- **结果：** **失败**。
- **关键失败行：** `s11 different at pc = 0x0080000020`，随后 `ABORT at pc = 0x80000020`；`instrCnt = 8` 即已失配。

### 测试边界（为何一开局就会挂）

- `lab1-extra-test.S` **首条指令** 为 `rem`（RISC-V **M 扩展**），随后大量 `mul`/`div`/`rem`/`mulw`/`divw`/`remw` 等。
- 当前译码第二段 `case (opcode)` **未包含** `0110011` 的 `funct3` 区分出 M 类乘除法，也未对 `mul`/`div` 等设置 `alu_op`；`common.sv` 中 `alu_op_t` 仅含 `ADD/SUB/ADDW/SUBW/AND/OR/XOR`，**无乘除余运算**。

因此：**Lab1-extra 失败既是实际 Difftest 结果，也是“测试探针超出当前 ALU/译码能力”的必然结果。**

---

## 4. Lab2：状态为「未通过标准测试；无真实访存与 U-type 写回」

### 实际测试

- **命令：** `./build/emu --diff ./ready-to-run/riscv64-nemu-interpreter-so -i ./ready-to-run/lab2/lab2-test.bin`。
- **结果：** **失败**。
- **关键失败行：** `a7 different at pc = 0x0080000014`，`right= 0x0000000040010000, wrong = 0x0000000000000000`，随后 `ABORT at pc = 0x80000014`；仅提交 **5** 条指令即失配。

### 测试边界与代码结构

- `lab2-test.S` 在极早期即使用 **`lui` + `addi` + `add`** 构造地址，并大量使用 **`lw`/`sw`/`lh`/`sh`/`lb`/`ld`/`sd`/`lhu`/`lwu`** 等访存指令。
- **`core_decode.sv`** 中虽对若干 opcode 计算了 `imm`（如 U-type 立即数），但 **没有在 `case` 中为 `lui`/`auipc` 等设置 `reg_write` 与写回语义**；**Load/Store** 也未设置 `mem_read`/`mem_write`/`wb_sel`（decode 默认清零后仅对部分 opcode 赋值）。
- **`core.sv`** 中数据总线请求被固定为无效：`assign dreq.valid = 1'b0`，地址/写数据/掩码均为 0，**MEM 阶段不向内存发起真实读写**。

因此：**Lab2 在 PC 尚未进入大量访存逻辑前，就会在 `lui` 等指令上因寄存器写回与参考模型不一致而失败**；这与“Lab2 需完整 load/store 与地址构造”的课程预期一致。

---

## 5. 小结表

| 阶段 | 标准 Makefile 目标 | 当前实现结论 | 主要依据 |
|------|-------------------|--------------|----------|
| **Lab1 基础** | `test-lab1` | **通过** | 实际运行 `HIT GOOD TRAP`；译码+ALU 覆盖 Lab1 算术/逻辑主路径。 |
| **Lab1-extra** | `test-lab1-extra` | **未通过** | 实测首段即寄存器失配；测试以 **M 扩展** 为主，RTL 无乘除译码与 ALU 操作。 |
| **Lab2** | `test-lab2` | **未通过** | 实测在 **`lui` 写回** 处失配；`dreq.valid` 恒 0，无真实访存，与 `lab2` 大量 load/store 需求不符。 |

---

## 6. 使用建议（若继续开发）

1. **先巩固 Lab1** 基线：保持 `test-lab1` 为回归门禁。  
2. **Lab1-extra：** 扩展译码与 ALU（或独立 M 级）以支持 `mul/div/rem` 等，再跑 `test-lab1-extra`。  
3. **Lab2：** 实现 **`lui`/`auipc` 等 U-type 写回**、**完整 `dreq`/`dresp` 握手与字节使能**，以及 load 的 **符号/零扩展与写回选择**，再跑 `test-lab2`。

（每次通过/失败边界变化后，建议同步更新 `.agents/skills/26-arch-project-assistant/status.md`，便于与仓库事实一致。）
