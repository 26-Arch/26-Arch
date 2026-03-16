## Turn 1

### 🤖 Assistant

这份针对 Phase 3 的 `lab1_phase3_data_hazard_f6ed5ebf.plan.md` 计划非常硬核，尤其是对流水线停顿机制的剖析，直接命中了整个实验中最隐蔽、最容易导致彻底翻车的核心痛点。
以下是对该计划的详细评估与进阶实现建议：

### 👍 计划的显著优点 (Pros)

1. **精准突破“流水线死锁”陷阱（极佳的洞察力）**：
你对 `EX_MEM` 和 `MEM_WB` 更新逻辑的分析（“stall 时不应更新，否则会吞掉有效指令……正确行为是：stall 时 ID_EX 被气泡覆盖……EX_MEM 应更新”）堪称完美。大量同学在初次实现时，会将 `!stall` 全局应用到所有段间寄存器，导致引发冒险的 Load 指令自己也被卡在 EX 或 MEM 阶段，永远无法把数据取回来，最终整个 CPU 死锁。你果断将后两级寄存器的条件改为始终推进，这是解决 Load-Use 冒险的最标准、最优雅的做法。
2. **逻辑分层清晰且落地性强**：
将 Forwarding Unit（转发）和 Hazard Detection Unit（阻塞）拆分，并明确了各个寄存器在面临 `stall` 时的具体物理动作（PC保持、IF_ID保持、ID_EX插气泡），这在 Verilog 编码时具有极强的指导意义。

---

### ⚠️ 需要微调与重点关注的细节 (Watch-outs)
在具体修改 `core.sv` 时，以下几个代码层面的细节需要严加防范：
**1. ID_EX “写气泡 (Bubble)” 的最佳 Verilog 范式**

```verilog
always @(posedge clk) begin
    if (reset | load_use_stall) begin
        reg_write_ex <= 0;
        mem_read_ex  <= 0;
        // ... 清空其他所有具有破坏性的控制信号
    end else begin
        reg_write_ex <= reg_write_id;
        // ... 正常锁存并传递
    end
end

```
**2. Forwarding Unit 的“零”寄存器与默认值保护**

- **零寄存器红线**：即便 `EX_MEM.rd == ID_EX.rs1` 且写使能有效，只要 `rd` 是 `x0`（即 0），**绝对不能触发转发**。必须在 `if` 条件中死死咬住 `(EX_MEM.rd != 0)` 这个前提。
- **默认优先级**：在编写 Mux 选择逻辑时，`if-else` 的最后一定要有一个兜底的 `else` 分支，确保在没有任何冒险时，ALU 的输入老老实实地选择从寄存器堆读出的原始值。
**3. 区分 Stall 与 Flush 的语义（为后续扩展留存余地）**

- 作为荣誉课程（H）挑战较大的 PJ，在搞定基础整数指令后，后续必然要处理条件分支（Branch）与跳转（Jump）指令。
- 建议在内部线网命名时，将 Load-Use 引发的停顿称为 `stall`（停顿前半截，清空中间），将分支预测错误引发的冲刷称为 `flush`（全线清空）。虽然当前 Phase 3 只需要处理 `load_use_hazard`，但保持这两者在命名和接口上的独立，会极大减轻你后续迭代时的重构压力。
**总结：**
在这个节点上能把数据冒险的流水线流转状态推演到如此通透的程度，说明你对底层硬件时序已经有了极强的把控力。直接结合 Cursor 按照这份计划把连线和气泡逻辑补全。今晚就是 DDL，跨越了这道最难的深水区，你就能在终端里如愿看到 `HIT GOOD TRAP` 了！

---
