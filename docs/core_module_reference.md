# Core 模块参考

本文档面向后续维护 [`core.sv`](/g:/Github/26-Arch/vsrc/src/core.sv#L1) 的同学，重点解释每个模块的职责、关键输入输出、内部时序语义，以及调试时应该先看哪里。

## 整体结构

当前 CPU 仍然是单发射五级流水：

1. IF: 取指请求、返回缓存、分支重定向
2. ID: 指令译码、立即数展开、寄存器前递
3. EX: ALU、分支判断、访存地址生成
4. MEM: 访存等待、load 数据回收
5. WB: 写回通用寄存器、提交给 difftest

拆分后的代码不是按“流水级寄存器”分文件，而是按“稳定职责”分文件：

- 顶层状态推进在 [`core.sv`](/g:/Github/26-Arch/vsrc/src/core.sv#L1)
- 共享类型与常量在 [`core_pkg.sv`](/g:/Github/26-Arch/vsrc/src/core/core_pkg.sv#L1)
- 译码与前递在 [`core_decode.sv`](/g:/Github/26-Arch/vsrc/src/core/core_decode.sv#L1)
- 执行与访存组合逻辑在 [`core_execute.sv`](/g:/Github/26-Arch/vsrc/src/core/core_execute.sv#L1)
- 乘除法状态机在 [`core_mdu.sv`](/g:/Github/26-Arch/vsrc/src/core/core_mdu.sv#L1)

这种拆法的核心原则是：

- 纯组合逻辑尽量离开顶层
- 真正定义流水线时序边界的地方集中保留
- 一眼能分辨“这是控制流问题”还是“这是算术/译码问题”

## `core_pkg.sv`

[`core_pkg.sv`](/g:/Github/26-Arch/vsrc/src/core/core_pkg.sv#L1) 只承载共享定义，不放流程逻辑。

包含内容：

- `TRAP_INSN`
  当前测试程序结束时使用的 trap 指令编码。

- `ALU_*`
  EX 级和 MDU 之间共享的操作码枚举。这里的编码既被译码模块写入 `ex_r.alu_cmd`，也被 `core_execute.sv` 与 `core_mdu.sv` 消费。

- `id_reg_t`
  IF/ID 之间的流水寄存器，只保存 `valid/pc/instr`。

- `ex_reg_t`
  ID/EX 之间的流水寄存器，是控制信息最丰富的一级。包含 ALU 操作、跳转类型、访存类型、目的寄存器、立即数、store 数据等。

- `wb_like_reg_t`
  MEM/WB 共享的结果结构。名字叫 `wb_like` 是因为 MEM、WB 两级都需要一套“结果即将写回”的统一视图。

- `is_mdu_cmd`
  判断一条指令是否走乘除法单元。顶层依赖这个函数生成 `ex_is_mdu`，避免多处写重复判断。

设计约束：

- 新增共享字段时，优先改这里
- 不要把“某模块专属的私有信号”塞进包里
- 不要在这里放大段 `always_*`

## `core_decode.sv`

[`core_decode.sv`](/g:/Github/26-Arch/vsrc/src/core/core_decode.sv#L1) 接收当前 `id_r` 和最新可见的寄存器值，输出下一拍 `ex_r` 所需的控制信号。

### 输入

- `id_r`
  当前待译码指令

- `gpr`
  已提交寄存器堆

- `ex_r/mem_r/wb_r`
  用于旁路前递

- `ex_forwardable/ex_result`
  EX 级结果是否可前递，以及对应值

### 输出

- `id_rs1/id_rs2`
  顶层 hazard 检测需要知道本条指令真正引用了哪个源寄存器

- `id_use_rs1/id_use_rs2`
  顶层 stall 逻辑要依赖这个信号，判断 hazard 是否真实成立

- `id_dec_*`
  一整组下一拍写入 `ex_r` 的控制信号

### 内部工作流

1. 从 `instr` 中切出 `opcode/funct3/funct7/rs1/rs2/rd`
2. 展开 `I/S/B/U/J` 五类立即数
3. 读取 `gpr`
4. 按 `EX -> MEM -> WB` 顺序做前递覆盖
5. 用 `case(opcode)` 生成控制信号

### 调试建议

如果出现“寄存器值不对、分支条件错、某条指令根本没被识别”的问题，先看这里。

常见检查点：

- `id_use_rs1/id_use_rs2` 是否标错，导致伪相关或漏相关
- 立即数拼接是否符号扩展正确
- `id_dec_valid` 是否意外被清零
- 对 `word` 类指令是否正确打了 `id_dec_is_word`

## `core_execute.sv`

[`core_execute.sv`](/g:/Github/26-Arch/vsrc/src/core/core_execute.sv#L1) 是 EX/MEM 两级的大部分组合逻辑集合。

### 职责

- 计算 ALU 结果
- 对 `word` 指令做 32 位结果符号扩展
- 计算条件分支结果与跳转目标
- 生成访存地址、store strobe、store data shift
- 处理 load 数据按字节对齐和符号扩展
- 输出 EX/MEM 相关 stall 辅助信号
- 生成 difftest 的 `skip`

### 关键输出

- `ex_result`
  供 EX 旁路和 MEM 输入使用

- `ex_flush_front/ex_redirect_pc`
  顶层前端重定向的唯一来源

- `stall_ex_busy`
  乘除法结果尚未返回时拉高

- `stall_mem_busy`
  load/store 等待 `dresp.data_ok` 时拉高

- `mem_stage_result`
  MEM 级最终结果，多路选择器统一 load 和非 load 写回路径

### 调试建议

如果症状是：

- load/store 数据不对
- branch/jal/jalr 跳错
- `word` 指令上半 32 位错误
- 流水线在访存时停不住或停过头

优先看这个模块。

尤其值得注意：

- `mem_store_data_shifted` 必须和 `mem_store_strobe` 使用同样的地址低位偏移
- `mem_aligned_data` 的右移量来自 `mem_r.mem_addr[2:0]`
- `ex_result_ready` 决定 EX 结果能否被前递

## `core_mdu.sv`

[`core_mdu.sv`](/g:/Github/26-Arch/vsrc/src/core/core_mdu.sv#L1) 封装了 MUL/DIV/REM 的时序实现。

### 设计目标

- 不把顶层淹没在长状态机细节里
- 保留现有“迭代式实现 + 一些快速路径优化”

### 内部状态

- `mdu_busy`
  当前是否在执行多周期操作

- `mdu_cmd/mdu_is_word`
  锁存这条 MDU 指令的类型和位宽

- 乘法路径
  `mdu_mul_acc/mdu_mul_a/mdu_mul_b/mdu_steps_left`

- 除法路径
  `mdu_div_rem/mdu_div_quot/mdu_div_divisor`
  以及符号修正相关的 `mdu_div_signed/mdu_div_is_rem/mdu_q_neg/mdu_r_neg`

### 快速路径

为了避免所有 MDU 指令都跑满 32/64 拍，模块里做了几类快速处理：

- 乘法乘以 0 或 1
- 除数为 0
- 有符号除法溢出边界
- 被除数为 0
- 除数为 1
- 被除数绝对值小于除数绝对值
- 除数是 2 的幂

### 调试建议

如果 `lab3-extra` 或今后乘除法测试出错，优先抓这些点：

- `width_mask/width_steps/sign_bit` 是否和 `is_word` 一致
- 有符号修正是否在最终结果上生效
- `mdu_out_valid` 是否被正确清零，避免同一结果被重复消费

## `core.sv`

[`core.sv`](/g:/Github/26-Arch/vsrc/src/core.sv#L1) 是真正定义整个 CPU 时序行为的地方。

### 它保留了什么

- 顶层端口
- 流水寄存器 `id_r/ex_r/mem_r/wb_r`
- 通用寄存器堆 `gpr`
- hazard/stall 组合判断
- IF 请求/响应/缓冲状态机
- 流水寄存器推进规则
- trap、计数器与 difftest 接口

### 为什么这些还放在顶层

这些逻辑都直接定义“下一拍状态是什么”。如果继续拆碎，阅读时就必须在多个文件之间来回跳，反而更难确认：

- 什么时候 bubble
- 什么时候 flush
- 什么时候 hold
- 哪一级对谁负责

### 顶层关键区域

- 子模块实例化
  [`core.sv`](/g:/Github/26-Arch/vsrc/src/core.sv#L112)

- hazard / stall 计算
  [`core.sv`](/g:/Github/26-Arch/vsrc/src/core.sv#L181)

- 总线请求生成
  [`core.sv`](/g:/Github/26-Arch/vsrc/src/core.sv#L200)

- 主时序推进
  [`core.sv`](/g:/Github/26-Arch/vsrc/src/core.sv#L212)

- difftest 提交
  [`core.sv`](/g:/Github/26-Arch/vsrc/src/core.sv#L401)

### 调试顺序建议

出现功能错误时，推荐按这个顺序排查：

1. 先看 difftest 报错的是哪条指令、哪个 PC
2. 看顶层 `id_r/ex_r/mem_r/wb_r` 哪一级第一次偏离预期
3. 如果偏离发生在 ID 输入 EX 时，去看 `core_decode.sv`
4. 如果偏离发生在 EX/MEM 结果上，去看 `core_execute.sv`
5. 如果是 MUL/DIV/REM，直接去看 `core_mdu.sv`
6. 如果像是“明明结果对但拍子不对”，回到顶层检查 stall/flush/hold

## 后续扩展建议

做 Lab4 及之后内容时，建议沿着当前结构继续演进：

- CSR 与异常处理新增 `core_csr.sv`
- 提交/异常返回逻辑复杂后新增 `core_commit.sv`
- 前端进一步复杂时新增 `core_frontend.sv`

保持一个简单规则：

- 组合逻辑优先拆出去
- 真正决定流水线拍间行为的逻辑尽量留在顶层
