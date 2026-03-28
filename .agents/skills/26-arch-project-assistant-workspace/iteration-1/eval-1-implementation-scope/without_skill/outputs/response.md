# 当前实现支持到哪一阶段（Lab1 基础 / Lab1-extra / Lab2）

下面结论同时对照了**仓库里的 RTL 与测试程序**、以及在本机对标准 Difftest 仿真的一次**实际运行**（使用已存在的 `build/emu`，与 `Makefile` 中 `test-lab*` 所用参数一致：`--diff ready-to-run/riscv64-nemu-interpreter-so` + 对应 `.bin`）。

---

## 总览

| 阶段 | 标准测试（Difftest） | 主要依据类型 |
|------|----------------------|--------------|
| **Lab1 基础** | **通过** | 实际测试结果 + 代码与 `lab1-test` 能力边界一致 |
| **Lab1-extra** | **未通过** | 实际测试结果 + 测试以 M 扩展为主、RTL 无乘除语义 |
| **Lab2** | **未通过** | 实际测试结果 + 无 `lui` 写回、无真实访存（代码结构） |

---

## Lab1 基础：已达到「标准验证可通过」

**实际测试结果：**  
执行：

```text
./build/emu --diff ./ready-to-run/riscv64-nemu-interpreter-so -i ./ready-to-run/lab1/lab1-test.bin
```

仿真在 `pc = 0x80010004` 处出现 **`HIT GOOD TRAP`**，说明在与 NEMU 参考模型对齐的前提下，Lab1 基线二进制能够跑完约定路径。

**代码与测试边界：**  
`vsrc/src/core.sv` 为五级流水线结构，含 `core_hazard_unit`、`core_forwarding_unit` 等；`core_decode.sv` / `core_alu.sv` 覆盖基础整数运算与常见 I 型、R 型、`addw`/`subw` 等路径，与 `ready-to-run/lab1/lab1-test.S` 所侧重的算术/逻辑类指令相匹配。  
**注意：** 能通过 Lab1 基础测试，只说明与**当前这份** `lab1-test` 一致，不自动等于「RV64I 全集」或后续实验的全部指令。

---

## Lab1-extra：未达到「标准测试可通过」

**实际测试结果：**  
同样方式运行 `lab1-extra-test.bin`，仿真 **ABORT**，典型报错为（摘录）：

```text
s11 different at pc = 0x0080000020, right= 0xffffffffffffffff, wrong = 0x0000000000000000
Core 0: ABORT at pc = 0x80000020
total guest instructions = 8
```

即在提交第 8 条有效指令附近，通用寄存器与参考模型不一致。

**测试边界：**  
`ready-to-run/lab1/lab1-extra-test.S` 对应的反汇编从 **`rem` / `mul` / `div` / `remu` 等 M 扩展指令**开始，并大量使用乘除模族指令。

**代码结构：**  
`core_alu.sv` 仅有 `ALU_ADD/SUB/AND/OR/XOR/ADDW/SUBW` 等，**没有**乘、除、取余；`core_decode.sv` 的 `opcode` 分支也未接入 `0110011` 下 `funct7` 区分 M 扩展的那一类译码。  
因此：**失败既是 Difftest 实测结果，也与「测试探针超出当前 ALU/译码能力」一致**，不是单纯偶发单点 bug 的表象。

---

## Lab2：未达到「标准测试可通过」

**实际测试结果：**  
运行 `lab2-test.bin`，仿真在很靠前的位置 **ABORT**，例如：

```text
a7 different at pc = 0x0080000014, right= 0x0000000040010000, wrong = 0x0000000000000000
Core 0: ABORT at pc = 0x80000014
total guest instructions = 5
```

参考模型期望寄存器 `a7`（`x17`）为 `0x40010000`，而实现侧为 `0`，对应指令为 **`lui`**（U-type）。

**测试边界：**  
`ready-to-run/lab2/lab2-test.S` 在极早期即出现 **`lui` + 算术构造地址**，并大量使用 **`lw` / `sw` / `lh` / `sh` / `lb` / `ld` 等访存**。

**代码结构：**  
- `core_decode.sv` 虽为 `0110111`/`0010111` 计算了 U-type 立即数，但**没有**为 `lui`/`auipc` 等设置 `reg_write` 与写回数据路径，因此 **`lui` 不会产生正确的寄存器更新**。  
- `core.sv` 中 **`assign dreq.valid = 1'b0`**，数据总线请求被关闭，**没有真实访存**。

故：**Lab2 在「U-type 写回」和「访存」两条主线上均未满足当前测试程序需求**；实测失败点与上述结构一致。

---

## 小结（如何区分三类依据）

1. **代码结构**：`dreq` 恒无效、译码/ALU 无 M 扩展、无 `lui` 写回——直接决定 Lab2 与 Lab1-extra 的上限。  
2. **测试边界**：反汇编可见 extra 以 M 指令为主、Lab2 以 `lui`+load/store 为主——与失败点可交叉验证。  
3. **实际测试结果**：Lab1 基线 **`HIT GOOD TRAP`**；extra 在 **div 类指令附近**寄存器失配；Lab2 在 **`lui` 处**即失配——为上述判断提供运行证据。

若你本地要复现完整流程（含重新编译仿真），可使用仓库标准目标：`make test-lab1`、`make test-lab1-extra`、`make test-lab2`（会先执行 `make sim` 再运行 `./build/emu`）。
