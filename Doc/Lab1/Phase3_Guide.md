# Lab1 Phase 3 学习指南：数据冒险处理

> 本文档面向初学者，用浅显的语言讲解 Phase 3 的工作内容与设计原理，便于后续学习与复习。

---

## 一、Phase 3 在做什么？

**目标**：解决流水线中的**数据冒险（Data Hazard）**，让依赖前序指令结果的指令能正确执行。

- Phase 1 搭好了流水线骨架，Phase 2 实现了译码与 ALU
- 但流水线中，后一条指令可能要用前一条**尚未写回寄存器**的结果（RAW 冒险）
- Phase 3 要：**转发（Forwarding）** 解决大部分 RAW；**阻塞与气泡（Stall & Bubble）** 解决 Load-Use 这类无法靠转发解决的冒险

可以类比为：流水线上后道工序需要前道刚出炉的半成品，不能傻等它入库，要直接从传送带上「截胡」；若前道是 Load（等内存），则只能暂停一拍。

---

## 二、Phase 3 涉及的两大机制

| 机制 | 解决什么问题 | 典型场景 |
|------|--------------|----------|
| **Forwarding（转发）** | 前序指令结果在 EX/MEM 或 MEM/WB，尚未写回 RegFile | `ADD x1, x2, x3` 后紧跟 `ADD x4, x1, x5` |
| **Stall & Bubble（阻塞与气泡）** | 前序是 Load，数据要到 MEM 末尾才有 | `LW x1, 0(x2)` 后紧跟 `ADD x3, x1, x4` |

---

## 三、核心概念：RAW 冒险与转发

### 3.1 什么是 RAW 冒险？

**RAW**：Read After Write。后一条指令要**读**的寄存器，正是前一条指令要**写**的。若前一条尚未写回，后一条会读到旧值。

**示例**：

```
ADD x1, x2, x3    ; 计算 x1，WB 阶段才写回
ADD x4, x1, x5    ; 需要 x1，但此时 x1 还在流水线里
```

若没有转发，第二条的 `rs1_data` 来自 RegFile，读到的是**旧值**。

### 3.2 转发的思路

前一条指令的结果在 **EX/MEM**（刚算完）或 **MEM/WB**（刚访存完）中，尚未写回 RegFile。我们可以直接从这两级「旁路」到 ALU 输入端，而不是等写回后再读。

**数据源**：

- **EX 冒险**：结果在 EX_MEM，用 `alu_result_mem`
- **MEM 冒险**：结果在 MEM_WB，用 `wb_data`（含 Load 结果）

### 3.3 双重冒险与优先级

考虑连续三条指令都写 x1：

```
ADD x1, x1, x2
ADD x1, x1, x3
ADD x4, x1, x5    ; rs1=x1 同时匹配前两条
```

此时 **EX 冒险优先于 MEM 冒险**（EX 的结果更新）。`if-else` 中必须把 EX 冒险的判断写在前面。

### 3.4 零寄存器红线

**x0 恒为 0**：即使 `rd_mem == rs1_ex` 且 `rd_mem == 0`，也**绝对不能**触发转发。必须在条件中显式包含 `rd != 0`。

---

## 四、Forwarding Unit 实现

### 4.1 位置与结构

在 **EX 阶段**，ALU 的 opA、opB 输入端前各增加一个 Mux，由 Forwarding Unit 控制选择。

### 4.2 opA 转发逻辑

```systemverilog
always_comb begin
    if (reg_write_mem && rd_mem != 5'b0 && rd_mem == rs1_ex)
        alu_opA = alu_result_mem;   // EX 冒险，优先级最高
    else if (reg_write_wb && rd_wb != 5'b0 && rd_wb == rs1_ex)
        alu_opA = wb_data;          // MEM 冒险
    else
        alu_opA = rs1_data_ex;      // 无冒险，用 RegFile 原始值
end
```

### 4.3 opB 转发逻辑

opB 在 `alu_src_ex = 0` 时用 rs2，需要同样的转发；`alu_src_ex = 1` 时用 imm，不受影响。

```systemverilog
logic [63:0] rs2_forwarded;
always_comb begin
    if (reg_write_mem && rd_mem != 5'b0 && rd_mem == rs2_ex)
        rs2_forwarded = alu_result_mem;
    else if (reg_write_wb && rd_wb != 5'b0 && rd_wb == rs2_ex)
        rs2_forwarded = wb_data;
    else
        rs2_forwarded = rs2_data_ex;
end
assign alu_opB = alu_src_ex ? imm_ex : rs2_forwarded;
```

### 4.4 关键要点

| 要点 | 说明 |
|------|------|
| EX 优先 | `if` 先判断 EX_MEM，`else if` 再判断 MEM_WB |
| rd != 0 | 条件中必须包含 `rd_mem != 5'b0`、`rd_wb != 5'b0` |
| else 兜底 | 最后必须有 `else`，无冒险时选 RegFile 原始值 |

---

## 五、Load-Use 冒险与 Stall

### 5.1 为什么转发不够？

Load 指令的数据要到 **MEM 阶段末尾**（`dresp.data`）才有。若下一条指令在 EX 阶段就要用这个数据，此时 Load 的结果还在 MEM，**转发网络来不及**（数据尚未进入 MEM_WB）。唯一办法：**暂停一拍**，等 Load 进入 MEM 拿到数据，下一拍再靠 MEM→EX 转发。

### 5.2 Hazard Detection Unit（冒险检测）

在 **ID 阶段** 检测 Load-Use 冒险：

```
load_use_hazard = ID_EX.mem_read && (ID_EX.rd != 0) && 
                  (ID_EX.rd == IF_ID.rs1 || ID_EX.rd == IF_ID.rs2)
```

即：EX 阶段是 Load，且其 `rd` 与 ID 阶段指令的 `rs1` 或 `rs2` 相同。

### 5.3 Stall 时的三件事

| 动作 | 实现 |
|------|------|
| **停住 PC** | `if (!stall) pc <= next_pc`，stall 时 PC 保持 |
| **停住 IF_ID** | `else if (!stall)` 更新，stall 时 IF_ID 保持 |
| **ID_EX 插气泡** | `if (reset \| load_use_hazard)` 时写 NOP，清零所有控制信号 |

### 5.4 ID_EX 气泡的 Verilog 范式（Phase3_PlanFix 推荐）

```systemverilog
always_ff @(posedge clk) begin
    if (reset || load_use_hazard) begin
        reg_write_ex <= 0;
        mem_read_ex  <= 0;
        mem_write_ex <= 0;
        inst_valid_ex <= 0;
        // ... 清空其他所有具有破坏性的控制信号
    end else begin
        reg_write_ex <= reg_write_id;
        mem_read_ex  <= mem_read_id;
        // ... 正常锁存并传递
    end
end
```

使用 `if (reset | load_use_hazard)` 统一处理气泡，`else` 正常锁存，而非 `else if (!stall)`。

---

## 六、EX_MEM、MEM_WB 与死锁规避

### 6.1 常见错误

若 EX_MEM、MEM_WB 也加上 `!stall` 条件，stall 时**不更新**，则引发冒险的 **Load 会卡在 EX 阶段**，永远进不了 MEM，拿不到数据，**流水线死锁**。

### 6.2 正确行为

- **PC、IF_ID**：stall 时保持（不取新指令，不覆盖 ID 的指令）
- **ID_EX**：stall 时写气泡（把 Load 的「消费者」挡住，插入 NOP）
- **EX_MEM、MEM_WB**：**stall 时仍推进**，让 Load 正常流动到 MEM、WB

因此需将 EX_MEM、MEM_WB 的 `else if (!stall)` 改为 `else`，使 stall 时仍正常更新。

---

## 七、Stall 与 Flush 的命名（Phase3_PlanFix）

- **stall**：Load-Use 引发的停顿，停前半截（PC、IF_ID），清空中间（ID_EX 插气泡）
- **flush**：分支预测错误引发的冲刷，全线清空（后续 Branch/Jump 用）

当前 Phase 3 仅需 `load_use_hazard`，但保持 `stall` 与 `flush` 在命名和接口上独立，便于后续扩展。

---

## 八、整体数据流示意

```
                    ID 阶段                                    EX 阶段
    ┌─────────────────────────────────────┐    ┌─────────────────────────────────────┐
    │  Hazard Detection Unit               │    │  rs1_data_ex ──┐                    │
    │  load_use_hazard = mem_read_ex &&   │    │                ├─► Forward Mux A ──►│
    │  rd匹配rs1/rs2                       │    │  alu_result_mem ─┘     alu_opA     │
    │         ↓                            │    │  wb_data ──────┘                    │
    │  stall = load_use_hazard             │    │                ┌─► Forward Mux B ──►│
    │         ↓                            │    │  rs2_data_ex ──┤     alu_opB       │
    │  PC 保持? IF_ID 保持? ID_EX 气泡?   │    │  alu_result_mem─┤                    │
    └─────────────────────────────────────┘    │  wb_data ──────┘       ALU          │
                                               └─────────────────────────────────────┘
```

---

## 九、Phase 3 红线与避坑

### 9.1 红线

| 红线 | 说明 |
|------|------|
| rd == 0 不转发 | 条件中必须显式包含 `rd != 0` |
| EX 冒险优先 | if-else 中 EX 判断在前 |
| else 兜底 | Forwarding Mux 最后必须有 else 选 RegFile |
| EX_MEM/MEM_WB 不卡 | stall 时仍推进，避免 Load 死锁 |

### 9.2 避坑要点（参考 Phase3_PlanFix）

| 问题 | 错误做法 | 正确做法 |
|------|----------|----------|
| ID_EX 气泡 | `else if (stall)` 时写气泡 | `if (reset \| load_use_hazard)` 写气泡，`else` 正常锁存 |
| 零寄存器 | 只判断 rd 匹配 | 必须加 `rd != 0` |
| 段间寄存器 | EX_MEM、MEM_WB 也加 !stall | 仅 PC、IF_ID 受 stall；EX_MEM、MEM_WB 始终推进 |

---

## 十、代码结构速查（Phase 3 相关）

| 位置 | 内容 |
|------|------|
| 213–216 | Hazard Detection：load_use_hazard、stall |
| 223–243 | Forwarding Mux：opA、opB（rs2_forwarded） |
| 174–211 | ID_EX：`if (reset \| load_use_hazard)` 气泡，`else` 正常 |
| 272–297 | EX_MEM：`else` 推进（无 !stall） |
| 312–331 | MEM_WB：`else` 推进（无 !stall） |

---

## 十一、验证与 Checklist

### 11.1 Forwarding

- [ ] opA、opB 各有一个 Forward Mux
- [ ] EX 冒险优先于 MEM 冒险
- [ ] `rd == 0` 不触发转发
- [ ] if-else 最后有 else 选 RegFile 原始值

### 11.2 Stall & Bubble

- [ ] load_use_hazard 条件正确（mem_read_ex、rd!=0、rs1/rs2 匹配）
- [ ] stall 接 load_use_hazard
- [ ] PC、IF_ID 在 stall 时保持
- [ ] ID_EX 使用 `reset | load_use_hazard` 写气泡
- [ ] EX_MEM、MEM_WB 去掉 !stall，stall 时仍推进

### 11.3 全局测试

- [ ] 运行 `make test-lab1`，确认无数据依赖导致的寄存器比对错误
- [ ] 报告中描述双重冒险与 Load-Use 阻塞的处理思路

---

## 十二、后续阶段预告

- **Phase 4**：仿真测试与提交；实现 Load/Store 后，Load-Use 框架将发挥作用
- **扩展**：Branch/Jump 需引入 `flush`，与 `stall` 区分

Phase 3 完成了数据冒险处理，为正确执行依赖密集的代码提供了硬件基础。
