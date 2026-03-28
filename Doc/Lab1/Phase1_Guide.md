# Lab1 Phase 1 学习指南：五级流水线骨架

> 本文档面向初学者，用浅显的语言讲解 Phase 1 的工作内容与设计原理，便于后续学习与复习。

---

## 一、Phase 1 在做什么？

**目标**：搭建一个 RISC-V 五级流水线 CPU 的「空壳子」。

- 不要求能正确执行指令（那是 Phase 2、3 的事）
- 只要求：**流水线结构正确**，指令能按阶段流动，各模块能正确连接

可以类比为：先搭好工厂的流水线传送带和工位，暂时不装具体加工设备。

---

## 二、五级流水线是什么？

一条指令从取到执行完成，要经历 5 个阶段：

| 阶段 | 英文 | 作用 |
|------|------|------|
| 1 | IF (Instruction Fetch) | 取指：根据 PC 从内存取指令 |
| 2 | ID (Instruction Decode) | 译码：解析指令，读寄存器 |
| 3 | EX (Execute) | 执行：ALU 运算 |
| 4 | MEM (Memory) | 访存：Load/Store 访问内存 |
| 5 | WB (Write Back) | 写回：把结果写回寄存器 |

**流水线的意义**：多条指令同时处于不同阶段，提高吞吐量。例如：

```
周期:  1    2    3    4    5    6    7
指令1: IF   ID   EX   MEM  WB
指令2:      IF   ID   EX   MEM  WB
指令3:           IF   ID   EX   MEM  WB
```

---

## 三、核心概念：组合逻辑 vs 时序逻辑

这是 Phase 1 最容易出错的地方。

### 3.1 组合逻辑（Combinational）

- **特点**：输入一变，输出立刻变，无记忆
- **写法**：`always_comb` 或 `assign`，用 `=` 赋值
- **用途**：译码、ALU 运算、多路选择等「当场算出来」的逻辑

### 3.2 时序逻辑（Sequential）

- **特点**：在时钟沿「锁存」数据，有记忆
- **写法**：`always_ff @(posedge clk)`，用 `<=` 赋值
- **用途**：PC、段间寄存器、寄存器堆写口

### 3.3 为什么必须区分？

- 段间寄存器如果用 `=`：会导致「打拍错误」，信号多延迟一拍
- 组合逻辑里用 `<=`：仿真和综合行为可能不一致

**记忆口诀**：段间寄存器 = 时序 + `<=`；阶段内部 = 组合 + `=`。

---

## 四、整体数据流

```
                    ┌─────────────────────────────────────────────────────────┐
                    │                      core 模块                           │
  ┌─────────┐       │                                                         │
  │  PC     │───────┼──► ireq.addr ──► 内存 ──► iresp.data ──► IF_ID_Reg     │
  │ (时序)   │       │                                                         │
  └────┬────┘       │    IF_ID_Reg ──► ID(译码+读Reg) ──► ID_EX_Reg          │
       │            │         ID_EX_Reg ──► EX(ALU) ──► EX_MEM_Reg            │
       │ next_pc    │         EX_MEM_Reg ──► MEM ──► MEM_WB_Reg               │
       └────────────┼──►     MEM_WB_Reg ──► WB ──► RegFile 写口               │
                    │              ▲                                          │
                    │              │ RegFile 读口 (rs1, rs2)                   │
                    │              └────────── ID 阶段                         │
                    └─────────────────────────────────────────────────────────┘
```

**关键**：信号只能通过段间寄存器一级一级往后传，不能「越级」直连。

---

## 五、各模块详解

### 5.1 寄存器堆 (RegFile)

**作用**：存储 32 个 64 位通用寄存器（x0～x31）。

- **x0 恒为 0**：RISC-V 规定，读 x0 永远得到 0，写 x0 无效
- **2 读 1 写**：ID 阶段同时读 rs1、rs2；WB 阶段写 rd
- **存储**：`rf[31:1]`，不存 x0

**代码对应**（`core.sv` 第 17–27 行）：

```systemverilog
logic [63:0] rf [31:1];   // 只存 x1～x31

// 写：仅在 WB 阶段、非 reset、rd≠0 时写入
always_ff @(posedge clk) begin
    if (!reset && reg_write_wb && rd_wb != 5'b0)
        rf[rd_wb] <= wb_data;
end

// 读：组合逻辑，rs1/rs2=0 时输出 0
rs1_data_id_r = (rs1_id == 5'b0) ? 64'b0 : rf[rs1_id];
rs2_data_id_r = (rs2_id == 5'b0) ? 64'b0 : rf[rs2_id];
```

---

### 5.2 PC 与 IF（取指）

**作用**：维护程序计数器，向内存发起取指请求。

- **PC 更新**：reset 时置为 `PCINIT`（0x8000_0000）；否则每周期 `PC + 4`
- **输出**：`ireq.valid = 1`，`ireq.addr = pc`
- **输入**：`iresp.data_ok` 表示指令已返回，`iresp.data` 为 32 位指令

**代码对应**（第 29–45 行）：

```systemverilog
assign next_pc = pc + 64'd4;   // RISC-V 每条指令 4 字节
assign stall   = 1'b0;         // Phase 1 不 stall

always_ff @(posedge clk) begin
    if (reset)
        pc <= PCINIT;
    else if (!stall)
        pc <= next_pc;
end

assign ireq.valid = ~stall;
assign ireq.addr  = pc;
```

---

### 5.3 IF_ID_Reg（取指→译码 段间寄存器）

**作用**：在时钟沿锁存 IF 阶段的输出，供 ID 使用。

- **锁存内容**：`pc`、`instr`（来自 `iresp.data`）、`inst_valid`（来自 `iresp.data_ok`）
- **inst_valid**：表示这条指令是否有效（取指成功为 1，Bubble 为 0），会一路传到 WB，用于 Difftest

**代码对应**（第 47–62 行）：

```systemverilog
always_ff @(posedge clk) begin
    if (reset) begin
        pc_id        <= 64'b0;
        instr_id     <= 32'b0;
        inst_valid_id <= 1'b0;
    end else if (!stall) begin
        pc_id        <= pc;
        instr_id     <= iresp.data;
        inst_valid_id <= iresp.data_ok;
    end
end
```

---

### 5.4 ID（译码）

**作用**：解析 32 位指令，读出寄存器，生成控制信号。

- **字段解析**：opcode、rd、rs1、rs2、funct3、funct7
- **立即数**：按 I/S/B/U/J 型格式拼接并符号扩展为 64 位
- **控制信号**：Phase 1 暂为占位（alu_op、mem_read 等全 0）

**RISC-V 指令格式速查**：

| 类型 | opcode 示例 | 立即数位置 |
|------|-------------|------------|
| I 型 | 0010011, 0000011 | imm[11:0] = instr[31:20] |
| S 型 | 0100011 | imm = {instr[31:25], instr[11:7]} |
| B 型 | 1100011 | imm = {instr[31], instr[7], instr[30:25], instr[11:8], 0} |
| U 型 | 0110111 | imm = {instr[31:12], 12'b0} |
| J 型 | 1101111 | imm = {instr[31], instr[19:12], instr[20], instr[30:21], 0} |

---

### 5.5 ID_EX_Reg、EX_MEM_Reg、MEM_WB_Reg

**作用**：与 IF_ID_Reg 相同，在时钟沿锁存前一阶段输出，供下一阶段使用。

**传递的信号**：

- **ID_EX**：pc、instr、inst_valid、rs1/rs2 数据、rd、imm、funct3/7、控制信号
- **EX_MEM**：pc、instr、inst_valid、alu_result、rs2_data（供 Store）、rd、控制信号
- **MEM_WB**：pc、instr、inst_valid、alu_result、mem_data、rd、控制信号

---

### 5.6 EX（执行）

**作用**：ALU 运算。Phase 1 仅为框架，默认输出 `rs1_data_ex`。

```systemverilog
always_comb begin
    alu_result_ex = rs1_data_ex;
    case (alu_op_ex)
        default: alu_result_ex = rs1_data_ex;
    endcase
end
```

Phase 2 会在此根据 opcode/funct3/funct7 实现 ADD、ADDI、XOR 等。

---

### 5.7 MEM（访存）

**作用**：Load/Store 访问内存。Phase 1 不发起访存，`dreq.valid = 0`。

---

### 5.8 WB（写回）

**作用**：选择写回数据（ALU 结果 或 内存数据），写回寄存器堆。

```systemverilog
assign wb_data = wb_sel_wb ? mem_data_wb : alu_result_wb;
// RegFile 写口在 5.1 节已实现
```

---

## 六、Difftest 连接

Difftest 用于将你的 CPU 与参考实现（NEMU）逐指令比对，验证正确性。

### 6.1 DifftestInstrCommit（指令提交）

每完成一条指令，需向 Difftest 报告：

- **valid**：用 `inst_valid_wb`，不能用 `reg_write_wb | mem_read_wb`（分支、NOP 不写寄存器也要提交）
- **pc、instr**：从 MEM_WB 传下来的
- **wen、wdest、wdata**：写寄存器信息
- **wdest**：必须 8 位，用 `{3'b0, rd_wb}` 补齐

### 6.2 DifftestArchIntRegState（寄存器状态）

**时序问题**：同一时钟沿，WB 写 RegFile，Difftest 读 RegFile，可能读到**写之前的旧值**。

**解决**：旁路（Bypass）。若 `gpr_i` 对应 `rd_wb` 且正在写，则用 `wb_data`；否则用 `rf[i]`。

```systemverilog
for (int i = 0; i < 32; i++) begin
    if (i == 0)
        gpr_dt[i] = 64'b0;
    else if (reg_write_wb && rd_wb == i[4:0])
        gpr_dt[i] = wb_data;   // 旁路
    else
        gpr_dt[i] = rf[i];
end
```

---

## 七、Phase 1 红线（必须遵守）

| 红线 | 说明 |
|------|------|
| 禁止 `*`、`/` | 乘除法需多周期实现，单周期组合逻辑会时序违例 |
| 段间用 `<=` | 段间寄存器必须用非阻塞赋值 |
| 组合用 `=` | 组合逻辑用阻塞赋值 |
| 禁止越级连线 | 信号必须经 IF_ID→ID_EX→EX_MEM→MEM_WB 传递 |

---

## 八、代码结构速查

| 行号 | 模块 | 类型 |
|------|------|------|
| 17–27 | RegFile | 时序写 + 组合读 |
| 29–45 | PC & IF | 时序 PC + 组合 ireq |
| 47–62 | IF_ID_Reg | 时序 |
| 64–116 | ID | 组合 |
| 118–164 | ID_EX_Reg | 时序 |
| 166–174 | EX ALU | 组合 |
| 176–206 | EX_MEM_Reg | 时序 |
| 208–214 | MEM | 组合（占位） |
| 216–244 | MEM_WB_Reg | 时序 |
| 246–259 | WB + gpr_dt | 组合 |
| 262–343 | Difftest | 接口连接 |

---

## 九、后续阶段预告

- **Phase 2**：实现约 12 条整数指令的译码与 ALU，实现 Load/Store
- **Phase 3**：实现转发（Forwarding）与阻塞（Stall），解决数据冒险

Phase 1 的骨架为这些扩展提供了清晰的数据通路与控制流基础。
