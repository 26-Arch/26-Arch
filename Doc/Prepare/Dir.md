# 目录介绍

整理一下本仓库与 Lab 相关的目录结构说明：

---

## 项目根目录概览

```
Arch-2026-Spring-FDU/
├── build/           # 仿真时生成，勿手动修改
├── difftest/        # 差分测试框架（子模块）
├── ready-to-run/    # 预编译测试用例
├── verilate/        # Verilator 仿真配置与 C++ 侧代码
├── vsrc/            # 你要写的 CPU 代码
├── Doc/             # 文档（含 Lab1 指导）
├── Makefile         # 仿真与提交入口
└── README.md
```

---

## 1. `vsrc/` —— 你的主要工作区

这是你实现 CPU 的地方，Lab1 的改动基本都在这里。

```
vsrc/
├── include/         # 头文件
│   ├── common.sv    # 公共类型、总线接口定义（ibus_req_t, dbus_req_t 等）
│   └── config.sv    # 配置参数
├── src/
│   └── core.sv      # CPU 核主体，Lab1 在这里实现 5 级流水线
├── util/            # 访存接口转换（框架提供，一般不改）
│   ├── IBusToCBus.sv
│   ├── DBusToCBus.sv
│   ├── CBusArbiter.sv
│   └── ...
└── SimTop.sv        # 仿真顶层，实例化 core 并连接总线
```

要点：

- `core.sv`：实现 IF / ID / EX / MEM / WB 及段间寄存器。
- `core` 通过 `ireq/iresp`（取指）和 `dreq/dresp`（访存）与外界交互。
- `common.sv` 定义了 `ibus_req_t`、`ibus_resp_t`、`dbus_req_t`、`dbus_resp_t` 等接口，需要按这些类型实现。
- `util/` 负责把 IBus/DBus 转成 CBus，Lab1 一般不需要修改。

---

## 2. `ready-to-run/` —— 测试用例

存放预编译好的测试程序，按 Lab 分目录：

```
ready-to-run/
├── lab1/
│   ├── lab1-test.bin      # Lab1 基础测试（make test-lab1 使用）
│   ├── lab1-test.S        # 对应汇编源码
│   ├── lab1-extra-test.bin # Lab1 附加测试
│   └── lab1-extra-test.S
└── lab2/
    └── ...                 # Lab2 测试
```

- `make test-lab1` 会加载 `lab1-test.bin`。
- `make test-lab1-extra` 会加载 `lab1-extra-test.bin`。
- `.S` 是汇编源码，调试时可对照查看。

---

## 3. `difftest/` —— 差分测试框架（子模块）

这是课程提供的 Difftest 框架，用于把你的 CPU 与参考实现（NEMU）逐指令对比。

```
difftest/
├── config/          # 配置
├── src/
│   ├── main/        # Scala 生成代码
│   └── test/
│       ├── csrc/    # C++ 仿真驱动、Difftest 逻辑
│       └── vsrc/   # 仿真用 Verilog（ram、ref 等）
├── verilator.mk     # Verilator 构建规则
└── ...
```

要点：

- 不要修改 `difftest/` 内部代码。
- 你的 `core` 通过 `SimTop` 被 Difftest 调用，它会比对你的 CPU 与 NEMU 的执行结果。
- `NEMU_HOME` 指向 `ready-to-run`，其中包含 NEMU 解释器 `riscv64-nemu-interpreter-so`。

---

## 4. `verilate/` —— Verilator 仿真配置

负责把 SystemVerilog 转成 C++ 并驱动仿真。

```
verilate/
├── Makefile.include       # 源文件列表、编译选项
├── Makefile.verilate.mk   # Verilator 构建
├── Makefile.vsim.mk       # 仿真运行
├── include/               # C++ 头文件
└── vsrc/                  # C++ 仿真代码（testbench、memory 等）
```

- 顶层通过 `Makefile.include` 等引入 `vsrc/SimTop.sv` 和 `core.sv`。
- 一般不需要改这里，除非要加调试或修改仿真行为。

---

## 5. `build/` —— 仿真产物目录

- 由 `make sim` 或 `make test-lab1` 自动创建。
- 存放 Verilator 生成的 C++ 和可执行文件 `emu`。
- 可随时 `make clean` 删除后重新生成。

---

## 6. `Makefile` —— 常用命令

| 命令 | 作用 |
|------|------|
| `make init` | 初始化子模块（首次克隆后执行） |
| `make sim` | 编译仿真，生成 `build/emu` |
| `make test-lab1` | 编译并运行 Lab1 基础测试 |
| `make test-lab1-extra` | 运行 Lab1 附加测试 |
| `make handin` | 打包 `vsrc`、`docs/report.pdf` 等生成提交 zip |
| `make clean` | 删除 `build/` |

---

## 7. `Doc/` —— 文档

```
Doc/
├── Lab1/
│   ├── Overall.md   # Lab1 四阶段总览
│   └── Phase1.md    # 阶段一骨架搭建细则
├── Env.md
├── Remote-Development-Environment-Setup.md
└── ...
```

---

## 数据流简要示意

```
make test-lab1
    ↓
make sim → 编译 vsrc/core.sv + SimTop + difftest
    ↓
build/emu --diff riscv64-nemu-interpreter-so -i ready-to-run/lab1/lab1-test.bin
    ↓
你的 core 取指(ireq/iresp)、访存(dreq/dresp) ↔ Difftest 与 NEMU 逐指令比对
    ↓
输出 HIT GOOD TRAP 表示通过
```

如果你希望，我可以再按「从 `core.sv` 到 `SimTop` 再到 Difftest」的调用链，逐层说明接口和信号流向。