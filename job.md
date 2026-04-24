# Lab1 任务清单（逐步执行）

## 目标

实现一个 64 位五级流水 CPU，通过 Lab1 基础测试；可选完成乘除法相关指令。

## 指令范围

- 必做：`addi xori ori andi add sub and or xor addiw addw subw`
- 选做：`mul div divu rem remu mulw divw divuw remw remuw`

## 开发步骤

### Step 0: 环境与基线

- 执行：`make init`
- 执行：`make test-lab1`
- 结果：确认当前基线失败方式可复现

通过标准：命令可运行，日志可用于后续对比。

### Step 1: 建立最小流水框架

- 在 `core.sv` 搭建 `Fetch/Decode/Execute/Memory/Writeback` 五级寄存结构
- 接通 `ireq/iresp` 取指主路径
- 暂时只实现最小可流动指令（如 `addi`）

通过标准：流水线前进正常，无死锁；单条简单程序可走通。

### Step 2: 完成整数 ALU 指令

- 完成 I/R 型算术逻辑：`addi xori ori andi add sub and or xor`
- 完成 32 位字操作：`addiw addw subw`
- 统一写回使能与 `x0` 写保护

通过标准：指令功能正确，写回值与参考一致。

### Step 3: 处理数据相关冒险

二选一（建议优先转发）：

- 方案 A：`stall`
- 方案 B：`forward`

最低要求：必须保证依赖指令结果正确。

通过标准：典型 RAW 依赖序列不出错。

### Step 4: 访存与总线时序收敛

- 明确 `ibus/dbus` 握手条件（`addr_ok/data_ok`）
- 处理等待周期，保证流水线停顿与恢复正确

通过标准：长延迟场景下无错误提交。

### Step 5: 对接 Difftest 提交信息

- 用真实提交信息驱动 `DifftestInstrCommit`
- 用真实寄存器状态驱动 `DifftestArchIntRegState`
- Trap/CSR 至少保持一致且不误报

通过标准：差分检查能稳定定位到真实错误，而非接口噪声。

### Step 6: 回归测试

- 执行：`make test-lab1`
- 若实现选做，再执行：`make test-lab1-extra`

通过标准：输出 `HIT GOOD TRAP`。

## 代码质量要求

- 单一职责：每级流水只做本级职责
- 显式有效位：流水寄存器包含 `valid`
- 明确默认值：组合逻辑给全默认，避免锁存器
- 统一命名：`*_valid/*_ready/*_wen/*_wdata`
- 最小改动原则：先跑通，再优化

## 每步自检清单

- 是否新增了可复现测试命令
- 是否只修改了当前步骤相关逻辑
- 是否补了必要注释（只解释关键设计点）
- 是否记录了失败现象与修复点

## 提交与打包

1. 在 `docs/` 放置报告：`docs/report.pdf`
2. 执行：`make handin`
3. 生成：`docs/<学号-姓名>-lab1.zip`
4. 只提交该 zip 到 Elearning

## 截止时间

- 截止：5 月 17 日 23:59
- 迟交扣分；代码不可运行会被大幅扣分
