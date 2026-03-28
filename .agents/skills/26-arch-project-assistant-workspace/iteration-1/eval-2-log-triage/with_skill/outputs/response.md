# make test-lab2 日志摘要

**当前范围**：一次完整的 `make test-lab2` 运行（基于你提供的终端输出；以下为日志解读，非重新执行测试）。

## 构建 vs 运行

- **构建**：成功。Verilator 完成综合报告并生成 C++，随后 `g++` 链接得到 `build/emu`，无编译/链接错误。
- **运行**：失败。仿真启动并完成若干条提交后，Difftest 报告寄存器不一致并 **ABORT**，不是 “HIT GOOD TRAP”。

## 最关键失败位置

- **首条决定性错误行**：`a7 different at pc = 0x0080000014, right= 0x0000000040010000, wrong = 0x0000000000000000`
- **随后中止**：`Core 0: ABORT at pc = 0x80000014`（与上同一 PC，仅省略高位写法不同）
- **上下文**：提交轨迹在 PC `0x80000014` 处对应指令编码 `400108b7`（RISC-V **LUI**，目标寄存器为 **a7**，立即数上域对应 `0x40010000`）。参考模型侧 **a7** 已为 `0x40010000`，设计侧仍为 `0`，因此在 **第 6 条提交** 起后续为全 0 占位。

## 最可疑的问题类型

- **Difftest 架构寄存器不一致**：属于 **功能/实现类**问题，而非构建或环境致命错误。
- 具体表现为 **LUI 写入 a7** 的语义在 DUT 与参考模型之间不一致（写回未发生、写错寄存器、提交顺序/使能错误，或该条指令未按预期提交等）。日志中的 `spike-dasm: not found` 与 `find ../src/main/scala` 缺失多为噪声或可选工具，**不是**本次失败的主因。

## 下一步最值得先看的文件

- 优先打开 **`vsrc/src/core.sv`**（以及与之相连的译码、写回、寄存器堆与提交路径），对照 PC `0x80000014` 上对 **a7** 的 **LUI** 行为，核对写回使能、目标寄存器编号与提交到 Difftest 的时机是否与参考一致。

---

**最小摘要（verification 风格）**

```text
Command: make test-lab2（日志记录）
Result: FAIL（运行期 Difftest）
Key line: a7 different at pc = 0x0080000014, right=0x40010000, wrong=0 → ABORT at pc = 0x80000014
Relevant detail: 指令 400108b7（LUI → a7），guest 仅完成 5 条有效指令相关路径
Next step: 查 vsrc/src/core.sv 及 LUI/a7 写回与提交路径
```
