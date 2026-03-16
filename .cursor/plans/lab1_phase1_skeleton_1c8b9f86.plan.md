---
name: Lab1 Phase1 Skeleton
overview: 在 [vsrc/src/core.sv](vsrc/src/core.sv) 中搭建 RISC-V 5 级流水线骨架：实现 5 个组合逻辑阶段模块（IF/ID/EX/MEM/WB）、4 个时序逻辑段间寄存器、寄存器堆，并按规范串联；同时正确连接 Difftest 接口。
todos:
  - id: regfile
    content: 实现 32x64 寄存器堆（2 读 1 写，x0 恒 0）
    status: completed
  - id: if-pc
    content: 实现 PC 与 IF 逻辑，驱动 ireq
    status: completed
  - id: if-id-reg
    content: 实现 IF_ID_Reg（含 inst_valid）
    status: completed
  - id: id-decode
    content: 实现 ID 译码与 RegFile 读
    status: completed
  - id: id-ex-reg
    content: 实现 ID_EX_Reg
    status: completed
  - id: ex-alu
    content: 实现 EX 与 ALU 框架
    status: completed
  - id: ex-mem-reg
    content: 实现 EX_MEM_Reg
    status: completed
  - id: mem-placeholder
    content: 实现 MEM 占位（dreq.valid=0）
    status: completed
  - id: mem-wb-reg
    content: 实现 MEM_WB_Reg
    status: completed
  - id: wb-regwrite
    content: 实现 WB 与 RegFile 写
    status: completed
  - id: difftest
    content: 连接 Difftest（inst_valid、旁路、wdest 位宽）
    status: completed
  - id: safety-check
    content: 代码审查（无 * /、无越级、段间用 <=）
    status: completed
isProject: false
---

# Lab1 Phase 1 骨架搭建实现计划

## 目标与约束

- **目标**：在 [vsrc/src/core.sv](vsrc/src/core.sv) 中建立 5 级流水线物理结构，不要求通过测试。
- **红线**：段间寄存器用 `always @(posedge clk)` + `<=`；阶段内用组合逻辑 + `=`；禁止 `*`、`/`；禁止越级连线。

---

## 1. 寄存器堆 (RegFile)

在 `core` 内部实现 32x64 位寄存器堆：

- 2 读口（rs1、rs2）、1 写口（WB 阶段）
- x0 恒为 0：读 rs1/rs2 时若地址为 0 则输出 0
- 写口：`we && (wa != 0)` 时写入 `wa`
- 使用 `logic [63:0] rf [31:1]` 存储，`always @(posedge clk)` 写，组合逻辑读

---

## 2. 段间寄存器信号规划

```mermaid
flowchart LR
    subgraph IF [IF]
        PC
        ireq
    end
    subgraph IF_ID [IF_ID_Reg]
        pc_id
        instr_id
    end
    subgraph ID [ID]
        Decode
        RegRead
    end
    subgraph ID_EX [ID_EX_Reg]
        pc_ex
        instr_ex
        rs1_data_ex
        rs2_data_ex
        rd_ex
        ctrl_ex
    end
    subgraph EX [EX]
        ALU
    end
    subgraph EX_MEM [EX_MEM_Reg]
        alu_result_mem
        rs2_data_mem
        rd_mem
        ctrl_mem
    end
    subgraph MEM [MEM]
        dreq
    end
    subgraph MEM_WB [MEM_WB_Reg]
        alu_result_wb
        mem_data_wb
        rd_wb
        ctrl_wb
    end
    subgraph WB [WB]
        RegWrite
    end
    IF --> IF_ID --> ID --> ID_EX --> EX --> EX_MEM --> MEM --> MEM_WB --> WB
```



**IF_ID**：`pc`, `instr`（32 位，来自 iresp.data）, `**inst_valid`**（取指成功时为 1，Bubble 时为 0）  
**ID_EX**：`pc`, `instr`, `inst_valid`, `rs1_data`, `rs2_data`, `rd`, `rs1`, `rs2`, `imm`, `funct3`, `funct7`, 控制信号  
**EX_MEM**：`pc`, `instr`, `inst_valid`, `alu_result`, `rs2_data`, `rd`, 控制信号  
**MEM_WB**：`pc`, `instr`, `inst_valid`, `alu_result`, `mem_data`（来自 dresp.data）, `rd`, 控制信号  

> **重要**：`inst_valid` 从 IF 起伴随 `instr`/`pc` 贯穿 4 个段间寄存器，用于 Difftest 的 valid 判断（分支、NOP 等不写寄存器的指令也需提交）。  

---

## 3. 各阶段模块实现要点

### 3.1 IF (Instruction Fetch)

- **组合逻辑**：`next_pc = pc + 64'd4`（仅顺序取指，无分支）
- **输出**：`ireq.valid = ~stall`, `ireq.addr = pc`
- **输入**：`iresp.data_ok` 时锁存指令到 IF_ID
- **inst_valid**：取指成功时 `inst_valid = iresp.data_ok`；插入 Bubble 时 `inst_valid = 0`。该信号随 instr/pc 贯穿 4 个段间寄存器。
- **PC 更新**：时序逻辑，`posedge clk`：`reset` 时 `pc <= PCINIT`，否则 `pc <= next_pc`
- **Stall**：当 `ireq.valid && !iresp.data_ok` 时，PC 与 IF_ID 不更新（Phase 1 可先假设内存单周期返回，后续再完善）

### 3.2 ID (Instruction Decode)

- **组合逻辑**：从 `instr_id` 解析 `opcode[6:0]`, `rd`, `rs1`, `rs2`, `funct3`, `funct7`，以及各型立即数（I/S/B/U/J）
- **寄存器读**：`rs1_data = (rs1==0) ? 0 : rf[rs1]`，`rs2` 同理
- **控制信号**：根据 opcode 生成 `alu_op`, `mem_read`, `mem_write`, `reg_write`, `wb_sel` 等（Phase 1 可先设默认值）

### 3.3 EX (Execute)

- **ALU**：`always @(*)` 或 `assign`，根据 `alu_op`/`funct3`/`funct7` 做 `case`，默认输出 0 或 rs1
- **Phase 1**：仅搭框架，如 `case (alu_op) default: alu_result = rs1_data; endcase`

### 3.4 MEM (Memory Access)

- **Phase 1**：`dreq.valid = 1'b0`，不发起访存
- **预留**：`dreq.addr`, `dreq.size`, `dreq.strobe`, `dreq.data` 等端口

### 3.5 WB (Write Back)

- **组合逻辑**：`wb_data = (wb_sel) ? mem_data : alu_result`
- **写寄存器**：`we && (rd_wb != 0)` 时 `rf[rd_wb] <= wb_data`，在 `always @(posedge clk)` 中完成

---

## 4. 四个段间寄存器

统一写法：

```systemverilog
always_ff @(posedge clk) begin
  if (reset) begin
    // 清空或置无效
  end else if (!stall) begin
    pc_id <= pc_if;
    instr_id <= iresp.data;
    // ...
  end
end
```

- 使用 `always_ff` 或 `always @(posedge clk)`
- 仅使用 `<=`
- `reset` 时清空，`stall` 时保持

---

## 5. Difftest 连接

将 WB 阶段输出接到 Difftest：

### 5.1 DifftestInstrCommit

- **valid**：使用 `inst_valid_wb`，而非 `reg_write_wb | mem_read_wb`。分支（BEQ/BNE）、NOP 等不写寄存器的指令也必须提交，否则 Difftest 会漏比。
- **pc**：`pc_wb`
- **instr**：从 MEM_WB 传下的 `instr_wb`
- **wen**：`reg_write_wb`
- **wdest**：**必须 8 位**，使用 `.wdest({3'b0, rd_wb})` 补齐
- **wdata**：`wb_data`

### 5.2 DifftestArchIntRegState（时序陷阱）

- **问题**：同一时钟沿 WB 写 RegFile、Difftest 读 RegFile 时，可能读到**写入前的旧值**。
- **正确做法**：对每个 `gpr_i`，若 `i == rd_wb && rd_wb != 0 && reg_write_wb`，则用 `wb_data` 旁路；否则用 RegFile 读出值。

### 5.3 其他

- **DifftestTrapEvent**：Phase 1 保持 `valid=0`
- **DifftestCSRState**：Phase 1 保持占位值

注意：`instr`、`inst_valid` 需从 IF_ID 经 ID_EX、EX_MEM 传到 MEM_WB，不能越级。

---

## 6. 顶层 core 内连接关系

```mermaid
flowchart TB
    PC[PC Reg]
    IF_ID[IF_ID_Reg]
    ID_EX[ID_EX_Reg]
    EX_MEM[EX_MEM_Reg]
    MEM_WB[MEM_WB_Reg]
    RF[RegFile]
    
    PC -->|pc| ireq
    iresp -->|instr| IF_ID
    IF_ID --> ID
    ID --> RF
    RF --> ID_EX
    ID_EX --> EX
    EX --> EX_MEM
    EX_MEM --> MEM
    MEM -->|dreq| dreq
    dresp --> MEM
    MEM --> MEM_WB
    MEM_WB --> WB
    WB --> RF
```



---

## 7. 实现顺序建议

1. 寄存器堆
2. PC 与 IF 逻辑，驱动 `ireq`
3. IF_ID_Reg
4. ID 译码与 RegFile 读
5. ID_EX_Reg
6. EX 与 ALU 框架
7. EX_MEM_Reg
8. MEM 占位（dreq.valid=0）
9. MEM_WB_Reg
10. WB 与 RegFile 写
11. 连接 Difftest
12. 检查：无 `*`/`/`，无越级连线，段间寄存器用 `<=`

---

## 8. 可选：内存就绪与 Stall（Phase 1 可简化）

若 `iresp.data_ok` 非单周期返回，可加：

- `stall = ireq.valid && !iresp.data_ok`
- `stall` 时：PC 不变，四个段间寄存器保持

Phase 1 可先假设 `data_ok` 单周期有效，若仿真异常再补 stall 逻辑。

---

## 9. 关键文件

- 所有实现均在 [vsrc/src/core.sv](vsrc/src/core.sv)
- 接口与类型见 [vsrc/include/common.sv](vsrc/include/common.sv)（`ibus_req_t`, `ibus_resp_t`, `dbus_req_t`, `dbus_resp_t`）
- 参数 `PCINIT = 64'h8000_0000` 在 common.sv

---

## 10. 避坑要点（参考 Phase1_PlanFix.md）


| 问题              | 错误做法                      | 正确做法                                |
| --------------- | ------------------------- | ----------------------------------- |
| Difftest valid  | 用 reg_write 或 mem_read 判断 | 用 inst_valid，从 IF 贯穿到 WB            |
| ArchIntRegState | 直接接 RegFile 读出            | WB 旁路：若 `i==rd_wb` 且写使能，用 `wb_data` |
| wdest 位宽        | 直接接 5 位 `rd_wb`           | 补齐为 8 位：`{3'b0, rd_wb}`             |


