# Lab1 Phase 2 学习指南：译码与执行

> 本文档面向初学者，用浅显的语言讲解 Phase 2 的工作内容与设计原理，便于后续学习与复习。

---

## 一、Phase 2 在做什么？

**目标**：让 CPU 具备**译码**和**算术/逻辑运算**能力。

- Phase 1 搭好了流水线骨架，但控制信号全是占位（0），ALU 也不做实际运算
- Phase 2 要：根据指令生成正确的控制信号，让 ALU 完成加减、与、或、异或等运算
- **范围**：仅 ID + EX，不涉及 Load/Store（Phase 3）和数据冒险（Phase 3）

可以类比为：在流水线上安装「翻译官」（ID）和「算盘」（ALU），让指令能被正确理解并执行。

---

## 二、Phase 2 涉及的两个阶段

| 阶段 | 职责 | Phase 2 新增内容 |
|------|------|------------------|
| ID | 译码 | 控制逻辑：alu_op、alu_src、reg_write |
| EX | 执行 | 操作数选择 Mux、ALU 实际运算 |

---

## 三、控制信号概览

### 3.1 需要生成并传递的信号

| 信号 | 含义 | 传递路径 |
|------|------|----------|
| alu_op | ALU 做哪种运算（加/减/与/或/异或/W 型） | ID → ID_EX → EX |
| alu_src | ALU 的 B 端用 rs2 还是 imm | ID → ID_EX → EX |
| reg_write | 是否写回寄存器 | ID → ID_EX → EX_MEM → MEM_WB → WB |

### 3.2 alu_src 的作用

ALU 有两个输入：A 端固定接 rs1，B 端需要选择：

- **alu_src = 0**：B 端接 rs2_data（R 型：ADD、SUB、AND、OR、XOR、ADDW、SUBW）
- **alu_src = 1**：B 端接 imm（I 型：ADDI、ADDIW、ANDI、ORI、XORI）

---

## 四、指令集与 opcode/funct 对应

### 4.1 支持的 12 条指令

| 指令 | opcode | funct3 | funct7 | 类型 | alu_src | 运算 |
|------|--------|--------|--------|------|---------|------|
| ADD | 0110011 | 000 | 0000000 | R | 0 | rs1 + rs2 |
| SUB | 0110011 | 000 | 0100000 | R | 0 | rs1 - rs2 |
| ADDW | 0111011 | 000 | 0000000 | R-W | 0 | 32 位加后符号扩展 |
| SUBW | 0111011 | 000 | 0100000 | R-W | 0 | 32 位减后符号扩展 |
| ADDI | 0010011 | 000 | - | I | 1 | rs1 + imm |
| ADDIW | 0011011 | 000 | - | I-W | 1 | 32 位加 imm 后符号扩展 |
| AND | 0110011 | 111 | 0000000 | R | 0 | rs1 & rs2 |
| OR | 0110011 | 110 | 0000000 | R | 0 | rs1 或 rs2 |
| XOR | 0110011 | 100 | 0000000 | R | 0 | rs1 ^ rs2 |
| ANDI | 0010011 | 111 | - | I | 1 | rs1 & imm |
| ORI | 0010011 | 110 | - | I | 1 | rs1 或 imm |
| XORI | 0010011 | 100 | - | I | 1 | rs1 ^ imm |

### 4.2 区分 ADD 与 SUB

R 型中，funct3 都是 000 时，用 **funct7 的 bit 5** 区分：

- funct7[5] = 0 → ADD
- funct7[5] = 1 → SUB（RISC-V 约定）

---

## 五、ID 阶段：控制逻辑

### 5.1 控制逻辑结构

用 `case (opcode_id)` 区分指令大类，再在 I 型、R 型中用 `case (funct3_id)` 区分具体指令：

```systemverilog
always_comb begin
    alu_op_id    = ALU_ADD;   // 默认
    alu_src_id   = 1'b0;
    reg_write_id = 1'b0;
    // ...

    case (opcode_id)
        7'b0010011: begin  // I-type ALU
            reg_write_id = 1'b1;
            alu_src_id   = 1'b1;
            case (funct3_id)
                3'b000: alu_op_id = ALU_ADD;   // ADDI
                3'b100: alu_op_id = ALU_XOR;   // XORI
                3'b110: alu_op_id = ALU_OR;    // ORI
                3'b111: alu_op_id = ALU_AND;   // ANDI
                default: ;
            endcase
        end
        7'b0011011: begin  // ADDIW
            reg_write_id = 1'b1;
            alu_src_id   = 1'b1;
            alu_op_id    = ALU_ADDW;
        end
        7'b0110011: begin  // R-type
            reg_write_id = 1'b1;
            case (funct3_id)
                3'b000: alu_op_id = (funct7_id[5]) ? ALU_SUB : ALU_ADD;
                3'b100: alu_op_id = ALU_XOR;
                3'b110: alu_op_id = ALU_OR;
                3'b111: alu_op_id = ALU_AND;
                default: ;
            endcase
        end
        7'b0111011: begin  // R-type W
            reg_write_id = 1'b1;
            alu_op_id    = (funct7_id[5]) ? ALU_SUBW : ALU_ADDW;
        end
        default: ;
    endcase
end
```

### 5.2 ImmGen 扩展

ADDIW 的 opcode 为 `0011011`，也使用 I 型立即数格式，需加入 ImmGen 的 case：

```systemverilog
7'b0010011, 7'b0000011, 7'b1100111, 7'b0011011: begin  // I-type (incl. ADDIW)
    imm_id = {{52{instr_id[31]}}, instr_id[31:20]};
end
```

**重要**：立即数必须符号扩展到 **64 位**，否则负数立即数会出错。

---

## 六、EX 阶段：操作数选择与 ALU

### 6.1 操作数选择（Operand Mux）

```systemverilog
assign alu_opA = rs1_data_ex;
assign alu_opB = alu_src_ex ? imm_ex : rs2_data_ex;
```

- alu_src_ex = 1：B 端用 imm（I 型）
- alu_src_ex = 0：B 端用 rs2_data（R 型）

### 6.2 ALU 操作码编码

| 常量 | 值 | 运算 |
|------|-----|------|
| ALU_ADD | 4'd0 | 64 位加法 |
| ALU_SUB | 4'd1 | 64 位减法 |
| ALU_ADDW | 4'd2 | 32 位加 + 符号扩展 |
| ALU_SUBW | 4'd3 | 32 位减 + 符号扩展 |
| ALU_AND | 4'd4 | 与 |
| ALU_OR | 4'd5 | 或 |
| ALU_XOR | 4'd6 | 异或 |

### 6.3 ALU 核心逻辑

64 位运算直接使用 `+`、`-`、`&`、`|`、`^`。**禁止使用 `*`、`/`**。

```systemverilog
case (alu_op_ex)
    ALU_ADD:  alu_result_ex = alu_opA + alu_opB;
    ALU_SUB:  alu_result_ex = alu_opA - alu_opB;
    ALU_AND:  alu_result_ex = alu_opA & alu_opB;
    ALU_OR:   alu_result_ex = alu_opA | alu_opB;
    ALU_XOR:  alu_result_ex = alu_opA ^ alu_opB;
    // ...
endcase
```

### 6.4 W 型指令（ADDW、SUBW、ADDIW）

**要求**：只对低 32 位运算，再将结果的 bit 31 符号扩展到高 32 位。

**错误**：直接 64 位运算再截断。

**正确**：

```systemverilog
ALU_ADDW: begin
    alu_res_32    = alu_opA[31:0] + alu_opB[31:0];
    alu_result_ex = {{32{alu_res_32[31]}}, alu_res_32};
end
ALU_SUBW: begin
    alu_res_32    = alu_opA[31:0] - alu_opB[31:0];
    alu_result_ex = {{32{alu_res_32[31]}}, alu_res_32};
end
```

`{{32{alu_res_32[31]}}, alu_res_32}` 表示：高 32 位重复 `alu_res_32[31]`（符号位），低 32 位为 `alu_res_32`。

---

## 七、段间寄存器：alu_src 透传

Phase 1 的 ID_EX_Reg 已传递 alu_op、reg_write、rd 等。Phase 2 需新增：

- **alu_src_id**（ID 输出）
- **alu_src_ex**（ID_EX 锁存）

在 ID_EX_Reg 的 `always_ff` 中增加：

```systemverilog
alu_src_ex <= alu_src_id;
```

---

## 八、数据流示意

```
                    ID 阶段                              EX 阶段
    ┌─────────────────────────────────┐    ┌─────────────────────────────────┐
    │  opcode, funct3, funct7         │    │  alu_opA = rs1_data_ex         │
    │         ↓                       │    │  alu_opB = alu_src ? imm : rs2  │
    │  Control Unit                   │    │         ↓                       │
    │  alu_op, alu_src, reg_write     │───►│  ALU (case alu_op_ex)           │
    │         ↓                       │    │         ↓                       │
    │  ID_EX_Reg 锁存                 │    │  alu_result_ex                  │
    └─────────────────────────────────┘    └─────────────────────────────────┘
```

---

## 九、Phase 2 红线与避坑

### 9.1 红线

| 红线 | 说明 |
|------|------|
| 禁止 `*`、`/` | 乘除法需多周期实现 |
| 控制与 ALU 用组合逻辑 | 使用 `always_comb` 或 `assign`，不用 `posedge clk` |

### 9.2 避坑要点（参考 Phase2_PlanFix）

| 问题 | 错误做法 | 正确做法 |
|------|----------|----------|
| ID_EX 透传 | 只加 alu_src | 核对 alu_op、reg_write、rd、rs1、rs2 等均透传 |
| ImmGen 位宽 | 12 位扩展到 32 位 | 必须扩展到 64 位 |
| W 型指令 | 64 位运算后截断 | 先 32 位运算，再符号扩展 |

---

## 十、代码结构速查（Phase 2 相关）

| 行号 | 内容 |
|------|------|
| 16–23 | ALU 操作码常量 |
| 78 | alu_src_id 声明 |
| 90–111 | ImmGen（含 ADDIW 的 0011011） |
| 113–154 | ID 控制逻辑 |
| 170 | alu_src_ex 声明 |
| 187, 206 | alu_src_ex 在 ID_EX 的 reset/锁存 |
| 214–240 | EX：操作数 Mux + ALU |

---

## 十一、验证要点

- **单条指令**：如 `ADDI x1, x0, 10` 应得到 x1 = 10
- **W 型**：`ADDIW x1, x0, 10` 应得到 x1 = 64'h0000_0000_0000_000a
- **全局搜索**：确认无 `*`、`/`
- **逻辑类型**：ALU 与译码均在组合逻辑中

---

## 十二、后续阶段预告

- **Phase 3**：实现转发（Forwarding）与阻塞（Stall），解决数据冒险；实现 Load/Store

Phase 2 完成了译码与执行，为 Phase 3 的数据冒险处理提供了正确的数据通路基础。
