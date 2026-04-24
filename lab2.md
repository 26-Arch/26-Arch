Lab2
Lab2 目标
要求 CPU 支持内存读写。

CPU 需要支持以下指令并通过测试：

ld, sd, lb, lh, lw, lbu, lhu, lwu, sb, sh, sw, lui

内存总线
在 实验讲解 中我们简单地介绍了如何使用内存总线取指，相当于一个固定的读 4 字节的读内存操作。

实际情况是，在流水线 CPU 中，Fetch 阶段和 Memory 阶段可能会同时发出访存请求，因此我们抽象出了独立的指令访存 ibus 和数据访存 dbus 接口。你可以了解一下它们是怎么做的，但是如果不想了解也暂时（在做 MMU 之前）没有关系，你只需要知道 ibus 是用来取指的，dbus 是用来读写数据的，并且它们的接口类似，都是根据 data_ok 和 addr_ok 信号来判断访存是否完成的。

然而，真实情况是我们并没有独立的“指令内存”和“数据内存”，ibus 和 dbus 访问的是同一块内存。这就可能会带来内存请求的冲突。为了解决这种冲突，我们使用一个仲裁器（CBusArbiter.sv）来协调 ibus 和 dbus 对内存的访问。

lab2 中，我们将加入内存读写的相关指令。你需要在 Memory 阶段加入对 dreq 和 dresp 信号的处理，实现内存的读取和修改。

dreq 信号的定义比 ireq 复杂一些：

字段名称	含义
valid	是否发出请求
addr	访存地址（起始字节）
size	访存大小（1 字节、2 字节、4 字节、8 字节）
strobe	字节使能，每一位对应一个字节是否需要写入，读取请保持全 0
data	写入的数据
内存在处理 dreq 时，会自动忽略 dreq.addr 的低 3 位，将其向下对齐到 8 字节。即 dreq.addr=64'h1F2 和 dreq.addr=64'b1F0 的效果是相同的（但你不应该在给总线的低 3 位设为 0，还是应该尊重指令中原始的地址）。

那么，如何实现向 0x1F2 写入 1 个字节的数据 0xCD 呢？这就需要配合 data, strobe 和 size 字段。

addr = 0x1F2（虽然内存会理解为 0x1F0，但是还是要写 0x1F2）
data = 0xCD0000（由于 addr 减了2， data 也左移2个字节，这样 0xCD 依然在对应的 0x1F2 位置）
strobe = 8'b0000_0100（表示仅 CD 对应的字节有效）
size = MSIZE1（表示访存 1 个字节，不过实际上因为有 strobe 存在，你设置为 MSIZE8 也不影响结果）
如果要读取内存，将 strobe 全置 0 即可。

更详细的说明，请参考 common.sv 中的注释

Lab2 测试
运行 make test-lab2，在输出中能看到 HIT GOOD TRAP 即为测试通过

---

## Lab2 实操记录（WSL，全流程逐步记录）

> 执行日期：2026-03-19  
> 执行环境：Windows PowerShell 调用 WSL（`wsl bash -lc ...`）

### Step 1：读取任务文档并确认目标

- 操作：
  - 阅读 `lab2.md` 原文要求
- 目标确认：
  - 支持 `ld, sd, lb, lh, lw, lbu, lhu, lwu, sb, sh, sw, lui`
  - 在 Memory 阶段处理 `dreq/dresp`
  - 最终应以测试输出 `HIT GOOD TRAP` 作为通过标志

### Step 2：在 WSL 中检查仓库与关键源码

- 命令：
  - `wsl bash -lc 'cd /mnt/g/Github/26-Arch && find vsrc -type f | sort'`
  - `wsl bash -lc 'cd /mnt/g/Github/26-Arch && sed -n "180,560p" vsrc/src/core.sv'`
- 关键检查结果：
  - `core.sv` 中已看到：
    - `dreq.valid/addr/size/strobe/data` 赋值
    - `dresp.data_ok` 驱动的 `mem_access_done/stall_mem_busy`
    - Load 指令（`LB/LH/LW/LD/LBU/LHU/LWU`）译码
    - Store 指令（`SB/SH/SW/SD`）译码
    - `LUI` 译码
    - 根据地址低 3 位做 `strobe` 与写数据左移对齐
    - 读回数据按地址低位右移后做符号/零扩展

### Step 3：按文档尝试执行 Lab2 测试命令

- 命令：
  - `wsl bash -lc 'cd /mnt/g/Github/26-Arch && make test-lab2'`
- 结果：
  - `make: *** No rule to make target 'test-lab2'.  Stop.`
- 结论：
  - 当前仓库 `Makefile` 无 `test-lab2` 目标，且 `ready-to-run` 目录仅有 `lab1` 测试镜像。

### Step 4：回归执行当前可用测试（WSL）

- 命令：
  - `wsl bash -lc 'cd /mnt/g/Github/26-Arch && make test-lab1'`
  - `wsl bash -lc 'cd /mnt/g/Github/26-Arch && make test-lab1-extra'`
- 关键输出：
  - `test-lab1`：`HIT GOOD TRAP at pc = 0x80010004`
  - `test-lab1-extra`：`HIT GOOD TRAP at pc = 0x8002001c`
- 结论：
  - 当前代码在现有公开测试下通过，流水线与访存相关逻辑可正常运行。

### Step 5：问题记录与处理说明

- 问题 1：`make test-lab2` 不存在  
  - 处理：检查 `Makefile`、`ready-to-run` 后确认仓库缺少 Lab2 专用目标与镜像，无法在本仓库内直接执行该命令。
- 问题 2：WSL 启动出现 `Failed to mount E:\` 提示  
  - 处理：该告警不影响 `/mnt/g/Github/26-Arch` 下构建与测试，任务继续执行。

### Step 6：最终状态

- Lab2 所需关键指令与 `dreq/dresp` 处理代码在 `vsrc/src/core.sv` 中已实现并接通。
- 当前仓库因缺少 `test-lab2` 目标/镜像，无法直接复现实验文档中的 Lab2 命令。
- 在可用测试下已完成构建与运行验证，均出现 `HIT GOOD TRAP`。

---

## Lab2 实操记录（WSL，二次更新：上游同步后）

> 执行日期：2026-03-19  
> 说明：上游更新后，仓库新增 `test-lab2` 目标与 `ready-to-run/lab2/lab2-test.bin`

### Step 7：确认上游更新已生效

- 命令：
  - `wsl bash -lc 'cd /mnt/g/Github/26-Arch && grep -n "test-lab" Makefile && find ready-to-run -maxdepth 3 -type f | sort'`
- 结果：
  - 确认存在 `test-lab2` 目标
  - 确认存在 `ready-to-run/lab2/lab2-test.bin`

### Step 8：首次执行 `make test-lab2` 并定位卡死

- 命令：
  - `wsl bash -lc 'cd /mnt/g/Github/26-Arch && make test-lab2'`
- 关键现象：
  - 输出 `No instruction ... commits for 5000 cycles`
  - 在前期访存后卡死
- 分析结论：
  - 死锁与总线仲裁期间请求稳定性相关，`CBusArbiter` 在事务处理中会看到请求变化，导致前端/访存互锁。

### Step 9：修复仲裁器请求保持逻辑

- 修改文件：
  - `vsrc/util/CBusArbiter.sv`
- 修改要点：
  - `busy` 期间由 `saved_req` 持续驱动总线，保证请求在事务结束前不变化
  - 当前事务 `oresp.last` 到达后先释放 `busy`，下一拍再接受新请求（避免同拍重复发起）

### Step 10：修复并发取指干扰

- 修改文件：
  - `vsrc/src/core.sv`
- 修改要点：
  - 将 `ireq.valid` 改为在 `stall_if_mem` 时拉低：
    - `ireq.valid = ... && !stall_if_mem;`
  - 让 Memory 阶段访存等待期间不再并发发起取指请求，避免 I/D 同时竞争引发请求抖动。

### Step 11：修正实验参数（按注释要求去掉 Lab2 的 DELAY=0）

- 修改文件：
  - `Makefile`
- 修改要点：
  - `DIFFTEST_OPTS =`（不再强制 `DELAY=0`）
  - 与 Makefile 注释 “remove on lab 2” 保持一致

### Step 12：最终验证通过

- 命令：
  - `wsl bash -lc 'cd /mnt/g/Github/26-Arch && make test-lab2'`
- 关键输出：
  - `HIT GOOD TRAP at pc = 0x8001fffc`
- 结论：
  - Lab2 测试已通过。
