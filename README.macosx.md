# macOS 运行说明

假设你已经有 Homebrew。

## 1. 安装依赖

先安装 Xcode Command Line Tools：

```sh
xcode-select --install
```

再通过 Homebrew 安装 Verilator：

```sh
brew install verilator
```

可选依赖：

```sh
brew install sdl2
brew install spike
```

说明：

- `sdl2` 只用于图形/键盘外设窗口。lab1 不需要它；没有安装时，构建会自动使用无 SDL 模式。
- `spike` 只用于把调试 trace 中的指令反汇编成人类可读文本。没有安装时，不影响 lab1 测试。

## 2. 确认工具可用

```sh
verilator --version
clang++ --version
make --version
```

本迁移已在 Homebrew Verilator `5.048` 和 Apple clang 环境下验证。

## 3. 运行 lab 测试

与 linux 无异。

## 4. macOS 迁移处理过的问题

本项目原本面向 Ubuntu，macOS 上主要差异如下：

1. 链接参数

   Linux 使用 `-static` 和 `-ldl`；macOS 不支持同样的静态链接方式，也不需要单独链接 `libdl`。现在 `difftest/verilator.mk` 会根据 `uname -s` 自动区分 Darwin 和 Linux。

2. SDL2

   Ubuntu 上通常可以直接 `#include <SDL2/SDL.h>` 并链接 `-lSDL2`。macOS 上 SDL2 可能没有安装，或没有进入默认 include/lib 搜索路径。现在构建系统会优先使用 `sdl2-config`；找不到时自动定义 `DIFFTEST_NO_SDL`，把图形/键盘事件退化为空实现。

3. Linux 专用头文件

   `sys/prctl.h` 是 Linux 专用头文件。现在只在 `__linux__` 下包含。

4. NEMU 动态库

   `ready-to-run/riscv64-nemu-interpreter-so` 是 Linux ELF shared object，macOS 不能通过 `dlopen` 加载它。
   
   但你们的助教经过亿点点改造成功跑起来了，目前有 `ready-to-run/riscv64-nemu-interpreter-so-apple` 用于 apple silicon arm64。

## 5. 清理与重跑

清理构建产物：

```sh
make clean
```
