# Core 模块化说明

## 目标

原先的 [`core.sv`](/g:/Github/26-Arch/vsrc/src/core.sv) 同时承担了以下职责：

- 流水寄存器定义
- 指令译码
- 执行级 ALU / 分支判断
- 访存对齐与回收
- 乘除法单元
- 顶层前端控制与提交逻辑
- difftest 对接

这些逻辑放在一个 1000+ 行文件里时，阅读和修改成本都很高。现在的重构目标是：

- 保留 `core` 作为唯一顶层入口，避免影响现有 `include "src/core.sv"` 的构建方式
- 将“纯组合逻辑”和“长时序状态机”拆开
- 让每个文件只负责一个稳定职责
- 用注释明确顶层控制点，方便后续定位流水线 bug

## 新的文件分工

- [`core.sv`](/g:/Github/26-Arch/vsrc/src/core.sv)
  顶层编排文件。保留流水寄存器、取指前端、流水级推进、寄存器写回、trap/halt、difftest 对接。

- [`core_pkg.sv`](/g:/Github/26-Arch/vsrc/src/core/core_pkg.sv)
  核心共享定义。包含 ALU/MDU 编码、trap 指令常量，以及 `ID/EX/MEM/WB` 相关结构体类型。

- [`core_decode.sv`](/g:/Github/26-Arch/vsrc/src/core/core_decode.sv)
  译码模块。负责寄存器前递后的源操作数选择、立即数展开、指令分类、控制信号生成。

- [`core_execute.sv`](/g:/Github/26-Arch/vsrc/src/core/core_execute.sv)
  执行与访存组合逻辑模块。负责 ALU 结果、分支跳转、访存地址/写掩码、load 数据回收，以及 EX/MEM 相关 stall 辅助信号。

- [`core_mdu.sv`](/g:/Github/26-Arch/vsrc/src/core/core_mdu.sv)
  乘除法单元。单独维护 MDU 内部状态，避免顶层被长状态机淹没。

## 数据流概览

流水线整体仍然是单发射、顺序提交的 5 级结构：

1. `core.sv` 管理取指请求、响应缓冲和重定向。
2. `core_decode.sv` 根据 `id_r` 和前递结果生成下一拍 `ex_r` 需要的控制信号。
3. `core_execute.sv` 组合计算 ALU、分支、访存辅助结果。
4. `core_mdu.sv` 只在乘除法指令上参与，给 EX 级提供延迟完成结果。
5. `core.sv` 统一推进 `ex_r -> mem_r -> wb_r`，并在提交时维护 `gpr` 与 difftest 状态。

## 为什么顶层还保留一部分逻辑

以下逻辑仍然放在顶层，是有意为之：

- 取指前端状态
  因为它同时依赖 `ireq/iresp` 握手、分支重定向、buffer 命中与停顿条件，拆太碎反而更难追踪。

- 流水级寄存器推进
  这是整个处理器“真实时序边界”的定义处，集中保留更容易检查 bubble / flush / hold 是否一致。

- trap 与 difftest
  这部分天然靠近提交点，继续放在 `WB` 附近可读性最好。

## 后续扩展建议

如果后面继续扩展功能，建议按以下原则保持结构整洁：

- 新增 CSR/异常体系时，优先加 `core_csr.sv` 或 `core_commit.sv`
- 如果分支预测或更复杂前端出现，再将当前 fetch 控制拆成 `core_frontend.sv`
- 保持 `core_pkg.sv` 只放共享类型/常量，不堆业务实现
