---
name: lab1 modular refactor
overview: Refactor the current monolithic `core.sv` into a thin top-level plus focused helper modules, while preserving the timing-sensitive pipeline register, stall, and Difftest behavior required by the Lab 1 experiment guide.
todos:
  - id: define-shared-types
    content: 在 `common.sv` 统一 ALU/控制相关 typedef，消除 `core.sv` 内部硬编码常量扩散
    status: completed
  - id: extract-decode
    content: 将字段提取、立即数生成、控制信号生成从 `core.sv` 拆到 `core_decode.sv`
    status: completed
  - id: extract-alu
    content: 将 EX 纯组合 ALU 拆到 `core_alu.sv`，保留现有 `ADDW/SUBW` 语义
    status: completed
  - id: extract-hazard-forward
    content: 将 load-use 检测与 forwarding 判断拆到独立模块，但保持顶层统一应用 stall/bubble/advance
    status: completed
  - id: extract-regfile
    content: 将整数寄存器堆拆到 `core_regfile.sv`，保留 x0 语义与写回时序
    status: completed
  - id: preserve-difftest-timing
    content: 在顶层保留 Difftest commit 和 GPR bypass，确保提交与寄存器可见性时序不变
    status: completed
  - id: run-regression
    content: 每步重构后运行 `make test-lab1` 验证未引入新的结构性回归
    status: completed
isProject: false
---

# Lab1 模块化重构计划

## 目标

按照实验讲解中“`core.sv` 是 CPU 核入口，但应拆成多个模块并在 `core.sv` 中例化”的要求，对当前实现做一次**保守、可验证**的模块化重构：先提取纯组合逻辑与独立存储模块，保留顶层对流水线寄存器、`stall`/后续 `flush`、以及 Difftest 时序的统一控制。

参考要求：实验讲解明确建议将代码拆成多个模块，并强调 Difftest 必须在提交时刻看到“恰好生效”的寄存器状态与提交信息。[实验讲解](https://github.com/26-Arch/26-Arch/wiki/%E5%AE%9E%E9%AA%8C%E8%AE%B2%E8%A7%A3)

## 当前问题

`[vsrc/src/core.sv](/home/thesumst/Data2/development/ComputerOrganization/26-Arch/vsrc/src/core.sv)` 目前同时承担：

- `RegFile` 存储与写回
- `PC/IF` 控制与 `ibus` 请求
- `IF_ID` / `ID_EX` / `EX_MEM` / `MEM_WB` 四组流水寄存器
- 指令 decode、立即数生成、控制信号生成
- forwarding / load-use hazard 检测
- ALU 组合逻辑
- Difftest commit 与 GPR 快照

其中最敏感的三类耦合不能在第一轮重构里打散：

- `stall` 的非对称语义：`PC`/`IF_ID` hold，`ID_EX` bubble，`EX_MEM`/`MEM_WB` 继续推进
- Difftest 看到的 GPR 状态必须带 WB bypass
- 未来 `fetch_wait` 会与 `stall` 共用前端控制通路，不能把前端时序拆散后各自改

## 推荐边界

第一轮仅拆出“无状态或局部状态”的模块：

- `[vsrc/src/core.sv](/home/thesumst/Data2/development/ComputerOrganization/26-Arch/vsrc/src/core.sv)`
  - 保留为顶层编排器
  - 继续拥有：全局 `stall`/后续 `flush`、所有流水寄存器、WB 选择、Difftest 接线
- 新增 `[vsrc/src/core_regfile.sv](/home/thesumst/Data2/development/ComputerOrganization/26-Arch/vsrc/src/core_regfile.sv)`
  - 封装 `rf` 存储、2 读 1 写、`x0` 恒零
  - 可选同时输出 Difftest 用的原始寄存器数组视图
- 新增 `[vsrc/src/core_decode.sv](/home/thesumst/Data2/development/ComputerOrganization/26-Arch/vsrc/src/core_decode.sv)`
  - 封装字段提取、立即数生成、控制信号生成
- 新增 `[vsrc/src/core_alu.sv](/home/thesumst/Data2/development/ComputerOrganization/26-Arch/vsrc/src/core_alu.sv)`
  - 纯组合 ALU
- 新增 `[vsrc/src/core_forwarding_unit.sv](/home/thesumst/Data2/development/ComputerOrganization/26-Arch/vsrc/src/core_forwarding_unit.sv)`
  - 只决定 `opA` / `rs2` 的前递选择
- 新增 `[vsrc/src/core_hazard_unit.sv](/home/thesumst/Data2/development/ComputerOrganization/26-Arch/vsrc/src/core_hazard_unit.sv)`
  - 只负责 `load_use_hazard` 等组合检测
- 视实现便利，在 `[vsrc/include/common.sv](/home/thesumst/Data2/development/ComputerOrganization/26-Arch/vsrc/include/common.sv)` 中补充统一 typedef
  - `alu_op_t`
  - decode/control bundle
  - 可能的 pipeline bundle（如果只定义类型而不马上拆寄存器）

## 不在第一轮做的事

以下内容先不动，避免把功能修复和结构重构耦合：

- 不把 `IF_ID` / `ID_EX` / `EX_MEM` / `MEM_WB` 分散到单独文件
- 不把 Difftest 封装进 `WBStage`
- 不引入完整 `IFStage` / `EXStage` / `MEMStage` 状态模块
- 不同时修复所有功能性 bug；先保证重构后行为等价，再继续查当前寄存器不匹配问题

## 实施顺序

```mermaid
flowchart LR
    currentCore[CurrentCore] --> extractDecode[ExtractDecode]
    extractDecode --> extractAlu[ExtractAlu]
    extractAlu --> extractHazard[ExtractHazardAndForward]
    extractHazard --> extractRegfile[ExtractRegFile]
    extractRegfile --> stabilizeTop[StabilizeTopLevelControl]
    stabilizeTop --> verify[RunLab1Regression]
    verify --> nextStep[ThenFixRemainingFunctionalBugs]
```



### 第 1 步：统一类型与接口

在 `[vsrc/include/common.sv](/home/thesumst/Data2/development/ComputerOrganization/26-Arch/vsrc/include/common.sv)` 定义最小公共类型，避免多个模块重复硬编码常量。

- 提取当前 `ALU_ADD`/`ALU_SUB`/`ALU_ADDW` 等编码为统一类型
- 为 decode 输出建立清晰的 control bundle 或至少一组统一 typedef
- 目标：后续模块接口可读、可复用，不改变现有时序

### 第 2 步：抽离 decode

把 `[vsrc/src/core.sv](/home/thesumst/Data2/development/ComputerOrganization/26-Arch/vsrc/src/core.sv)` 中的这部分搬到 `[vsrc/src/core_decode.sv](/home/thesumst/Data2/development/ComputerOrganization/26-Arch/vsrc/src/core_decode.sv)`：

- `opcode/rd/rs1/rs2/funct3/funct7` 提取
- `imm_id` 组合逻辑
- `alu_op_id` / `alu_src_id` / `reg_write_id` / `mem_read_id` / `mem_write_id` / `wb_sel_id`

顶层仍负责：

- `instr_id` 的来源
- `ID_EX` 锁存
- 所有 bubble 行为

### 第 3 步：抽离 ALU

把 EX 的纯组合计算提到 `[vsrc/src/core_alu.sv](/home/thesumst/Data2/development/ComputerOrganization/26-Arch/vsrc/src/core_alu.sv)`。

- 输入：`alu_op`, `opA`, `opB`
- 输出：`result`
- `ADDW/SUBW` 的 32 位结果再符号扩展保留不变

这样可以把功能错误和组合逻辑定位得更清楚。

### 第 4 步：抽离 Forwarding/Hazard

新增：

- `[vsrc/src/core_forwarding_unit.sv](/home/thesumst/Data2/development/ComputerOrganization/26-Arch/vsrc/src/core_forwarding_unit.sv)`
- `[vsrc/src/core_hazard_unit.sv](/home/thesumst/Data2/development/ComputerOrganization/26-Arch/vsrc/src/core_hazard_unit.sv)`

要求：

- 这两个模块只输出“判断结果/选择信号”，不直接修改流水寄存器
- `core.sv` 继续统一执行：`stall`、`ID_EX bubble`、`EX_MEM/MEM_WB advance`

这样能保住实验讲解要求的时序语义，尤其是 Difftest 与冒险控制之间的耦合。

### 第 5 步：抽离 RegFile

新增 `[vsrc/src/core_regfile.sv](/home/thesumst/Data2/development/ComputerOrganization/26-Arch/vsrc/src/core_regfile.sv)`。

- 封装 `rf[31:1]`、同步写、组合读、`x0=0`
- 顶层继续生成 `gpr_dt`（或由 RegFile 显式输出 raw regs，再由顶层做 WB bypass）
- 不把 Difftest 放进 RegFile；仍由顶层组织 commit 与 GPR 对外视图

## 顶层重构后的职责

重构后 `[vsrc/src/core.sv](/home/thesumst/Data2/development/ComputerOrganization/26-Arch/vsrc/src/core.sv)` 应主要保留：

- 顶层 IO 和各子模块连线
- `pc` 与 `ireq`
- `IF_ID` / `ID_EX` / `EX_MEM` / `MEM_WB` 时序块
- `stall` / `fetch_wait` / 未来 `flush` 的统一决策
- `wb_data` 选择
- Difftest commit 与 `gpr_dt`

## 验证策略

每抽离一个模块，都做一次最小回归：

- 编译通过
- `make test-lab1`
- 若失败，先确认是功能回归还是原有 bug 继续存在

重点观察：

- 第一条提交必须仍是 `PCINIT`
- `DifftestInstrCommit.valid` 仍由 `inst_valid_wb` 驱动
- `gpr_dt` 仍对 `rd_wb/wb_data` 做 same-cycle bypass
- `stall` 时 `EX_MEM` / `MEM_WB` 不得被错误冻结

## 完成标准

- `core.sv` 明显瘦身，只保留顶层编排与关键时序控制
- decode / ALU / forwarding / hazard / regfile 分别有独立文件
- 行为与当前实现保持一致，不引入新的 Difftest 时序错误
- 为后续继续修复当前 Lab1 功能 bug 提供更清晰的定位基础

