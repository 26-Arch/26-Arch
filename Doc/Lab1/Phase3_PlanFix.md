# Lab1 Phase 3 Fix 复盘

> 本文档不是新的实现计划，而是对 Phase 3 实际调试过程的复盘总结，重点解释：
> 1. 当时到底报了什么错
> 2. 根因是什么
> 3. 为什么最后的正确修复在 `vsrc`，而不应该改 `difftest`

---

## 一、最终结论

Phase 3 最后能够跑通 `make test-lab1`，不是只靠“补 Forwarding + Load-Use Stall”就结束了，而是还额外修复了两个**容易被忽略的系统级问题**：

1. **取指握手（ibus protocol）没有满足实验讲解要求**
2. **程序结束时没有通过 `DifftestTrapEvent` 正确上报 GOOD TRAP**

这两个问题都不属于“算术逻辑单元本身算错”，而属于：

- 流水线控制与外部总线协议的交互
- Difftest 接线与提交/结束时序

---

## 二、问题暴露的顺序

### 2.1 第一阶段：5000 周期无提交

最开始的测试输出是：

```text
No instruction commits for 5000 cycles of core 0. Please check the first instruction.
```

同时：

- `Commit Group Trace` 全是 `pc 0000000000 cmtcnt 0`
- `Commit Instr Trace` 全是 `inst 00000000`

这说明：

- 不是“某条指令提交后比对失败”
- 而是**连第一条指令都没有成功提交**

换句话说，CPU 卡在了**取指/有效位传播/首条 commit 建立之前**。

### 2.2 第二阶段：`this_pc` 不匹配

修完首个问题后，测试继续向前推进，出现了：

```text
this_pc different at pc = 0x0080000004
```

这说明：

- 第一条指令已经成功提交
- Difftest 已经真正开始逐条比较
- 失败点从“没有 commit”推进到了“架构状态比较”

### 2.3 第三阶段：寄存器错误

继续处理后，失败点又推进到：

```text
s11 different at pc = 0x0080000010
```

这个阶段看起来像是 `addi` 或转发错误，但本质上不是 ALU 算错，而是 **commit 在某些等待周期里被重复送给 Difftest**，导致参考模型和 DUT 的执行步数发生错位。

### 2.4 第四阶段：NEMU 已经 GOOD TRAP，但仿真不结束

再往后，日志里已经能看到：

```text
nemu: HIT GOOD TRAP
```

但仿真没有正常结束，而是一直刷：

```text
Program execution has ended. To restart the program, exit NEMU and run again.
```

这说明：

- 测试程序实际上已经跑到了末尾
- 参考侧已经知道程序结束
- 但 DUT 没有通过 `DifftestTrapEvent` 把“结束”告诉仿真框架

---

## 三、真正的根因分析

## 3.1 根因一：取指握手违反 ibus 规则

根据实验讲解：

- 发出取指请求后
- 在 `iresp.data_ok` 变成 1 之前
- `ireq.valid` 和 `ireq.addr` 必须保持不变

参考要求见：[实验讲解](https://github.com/26-Arch/26-Arch/wiki/%E5%AE%9E%E9%AA%8C%E8%AE%B2%E8%A7%A3)

而当时的前端写法本质上是：

- `stall` 只由 `load_use_hazard` 控制
- 没有 `fetch_wait`
- 只要没有 data hazard，`pc` 就持续 `+4`
- `ireq.addr` 又直接等于 `pc`

于是会出现：

- 还没等到当前这条取指的 `data_ok`
- 下一拍 `pc` 已经改成新地址
- `ireq.addr` 也随之改变

这会破坏总线协议，导致：

- 取指响应和请求错位
- `inst_valid_id` 难以正确建立
- `inst_valid_ex/mem/wb` 全部变成 bubble
- 最终 5000 周期无提交

### 正确修复

补一个前端等待状态：

```systemverilog
assign fetch_wait = ireq.valid && !iresp.data_ok;
assign stall = load_use_hazard || fetch_wait;
assign ireq.valid = ~load_use_hazard;
```

核心思想是：

- **等待响应时，PC 和 IF_ID 不动**
- **请求 valid 继续保持**
- **直到 `data_ok` 到来后才推进**

这一步修好后，第一条指令恢复提交。

---

## 3.2 根因二：WB 指令在等待周期被重复提交

修好前端后，后面出现寄存器错误。进一步观察 commit trace，可以发现同一条指令被重复上报：

- 同一个 `pc`
- 同一条 `instr`
- 连续多次出现在 commit trace 中

这说明：

- `MEM_WB` 在某些条件下保持
- 但 `DifftestInstrCommit.valid` 仍然保持为 1
- Difftest 把同一条 WB 指令当成多次提交

这样会导致：

- REF 多执行几条“重复指令”
- DUT 和 REF 的架构状态从某个时刻开始错位
- 表面上看像寄存器算错，实际上是**提交协议错了**

### 正确修复

不要直接把 `inst_valid_wb` 原样送给 Difftest，而是只在本拍真的发生有效提交时拉高：

```systemverilog
assign commit_valid_wb = inst_valid_wb && !fetch_wait;
```

然后：

```systemverilog
.valid(commit_valid_wb)
```

这样同一条指令不会在 WB 保持期间被重复提交。

---

## 3.3 根因三：没有正确实现 `DifftestTrapEvent`

实验跑到最后时，测试程序尾部会执行特殊 trap 指令：

```text
10004: 0005006b
```

这条不是普通算术指令，而是用来告诉 difftest/仿真框架：

- 程序结束了
- 结束码是多少
- 当前 pc / cycleCnt / instrCnt 是多少

如果 RTL 里始终把：

```systemverilog
DifftestTrapEvent.valid = 0
```

那么即使：

- 程序实际上已经跑完
- NEMU 已经输出 `HIT GOOD TRAP`

仿真框架仍然不知道 DUT 已经结束，于是会继续执行，最终表现为：

- 一直刷 `Program execution has ended`
- 测试不正常收敛

### 正确修复

在 WB 侧识别 trap 指令：

```systemverilog
localparam logic [31:0] TRAP_INST = 32'h0005006b;
assign is_trap_wb = inst_valid_wb && (instr_wb == TRAP_INST);
assign trap_valid_wb = is_trap_wb && !fetch_wait;
assign trap_code_wb = rf_dbg[10][7:0];
```

并把它接到：

```systemverilog
DifftestTrapEvent
```

同时维护：

- `cycle_cnt`
- `instr_cnt`

这样仿真框架才能在正确时刻结束。

---

## 四、为什么不应该改 `difftest`

调试过程中，曾为了快速验证 `this_pc` 比较逻辑，临时修改过 `difftest/src/test/csrc/difftest/difftest.cpp`。

这类修改的用途只是：

- 帮助定位问题
- 判断错误到底在 RTL 还是在比较逻辑

但它**不应该成为最终修复方案**，原因有三：

1. **实验要求主要修改 `vsrc`**
   - 实验讲解明确说 CPU 实现应写在 `vsrc`
   - 除非非常清楚自己在做什么，否则不应改 `vsrc` 以外文件

2. **`difftest` 是测试框架，不是被测设计**
   - 改测试框架可能掩盖 RTL 的真实错误
   - 最终提交也不应依赖这类改动

3. **正确问题最终都能在 RTL 中解释**
   - 首条无提交：是取指握手问题
   - 寄存器错位：是重复 commit 问题
   - 程序不结束：是 trap 接线问题

所以最终保留的修复应当全部落在：

- `vsrc/src/core.sv`
- 以及你拆分出的辅助模块

而不应该保留对 `difftest` 的修改。

---

## 五、最终保留的修复点

最终应保留、且确实解决问题的 RTL 修复如下：

| 修复点 | 作用 |
|------|------|
| `fetch_wait` | 等待取指响应，保证 `data_ok` 前请求稳定 |
| `stall = load_use_hazard || fetch_wait` | 统一前端停顿条件 |
| `ireq.valid = ~load_use_hazard` | 等待取指时不撤销请求 |
| `IF_ID` / `PC` 在 `stall` 时保持 | 避免取指与译码错位 |
| `ID_EX` 在 `load_use_hazard` 时插 bubble | 正确处理 Load-Use 冒险 |
| `EX_MEM` / `MEM_WB` 在 `fetch_wait` 时保持 | 防止错误推进/重复提交 |
| `commit_valid_wb = inst_valid_wb && !fetch_wait` | 防止同一条 WB 指令重复提交 |
| `DifftestTrapEvent` 接线 | 在 GOOD TRAP 处正常结束仿真 |

---

## 六、最终验证结果

最终 `make test-lab1` 输出为：

```text
The first instruction of core 0 has commited. Difftest enabled.
Core 0: HIT GOOD TRAP at pc = 0x80010004
total guest instructions = 16,385
instrCnt = 16,385, cycleCnt = 32,779, IPC = 0.499863
```

这说明：

- 第一条指令已经能正确提交
- 中间没有寄存器比对错误
- 程序能正常跑到 trap
- 仿真能正确收敛结束

---

## 七、给后续自己的提醒

如果以后又看到类似问题，可以按这个顺序排查：

1. **先看有没有第一条 commit**
   - 没有：优先查 fetch/ibus/inst_valid
2. **再看 commit 是否重复**
   - 同一条 `pc` 重复出现：优先查 WB 提交脉冲
3. **再看是否能正常结束**
   - NEMU 已 GOOD TRAP 但仿真不停：优先查 `DifftestTrapEvent`
4. **最后才查具体 ALU/Forwarding 数值**
   - 因为很多“寄存器错”其实是提交协议或流水线控制错位导致的表象

---

## 八、与 `Phase3_Guide` 的关系

- [`Phase3_Guide.md`](./Phase3_Guide.md) 适合学习“原理与实现方式”
- 本文档适合复盘“这次具体是怎么翻车、怎么救回来的”

建议两个文件配合看：

- 先看 `Guide` 理解机制
- 再看 `PlanFix` 理解真实调试路径
