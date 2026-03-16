# Remote Development Environment Setup

**Date**: March 17, 2026 at 12:28 AM
**Turns**: 1
**Source**: [Gemini Chat](https://gemini.google.com/app/679def93fbf81416)

---

## Turn 1

### 🤖 Assistant

既然你拥有 Ubuntu 实体机并希望通过 SSH 远程连接进行开发，而不使用图形化桌面，我为你规划了一套**“远程开发驱动型”**的配置流程。
这套方案的核心是：**Linux 作为高性能算力服务器（运行 Verilator 仿真、编译），Windows 作为 UI 交互端（VS Code 写代码、GTKWave 看波形）。**

---

### 第一阶段：Ubuntu 实体机（服务端）配置
通过 SSH 连接到你的 Ubuntu，依次执行以下任务。

#### 1. 基础依赖与 Verilator 编译
这些是编译 CPU 仿真器必须的工具链。

```bash
# 更新并安装依赖
sudo apt update
sudo apt install -y git help2man perl python3 make autoconf g++ flex bison ccache libgoogle-perftools-dev numactl perl-doc libsdl2-dev

# 源码编译安装 Verilator (v5.032)
cd ~
git clone https://github.com/verilator/verilator.git
cd verilator
git checkout v5.032
autoconf
./configure
make -j$(nproc)  # 自动使用所有 CPU 核心加速编译
sudo make install
verilator --version

```

#### 2. 克隆实验仓库

```bash
mkdir ~/arch_2026 && cd ~/arch_2026
git clone https://github.com/26-Arch/26-Arch.git
cd 26-Arch
git submodule update --init --recursive  # 关键：同步 difftest 子模块

```

#### 3. 安装后端语法支持工具 (CTags)
为了让远程 VS Code 能实现符号跳转。

```bash
cd ~
git clone https://gitlab.com/fudan-systa/ctags.git
cd ctags
./autogen.sh && ./configure && sudo make && sudo make install

```

---

### 第二阶段：Windows 端（开发交互端）配置
你无需在 Ubuntu 上打开任何窗口，所有操作都在 Windows 上完成。

#### 1. VS Code 远程连接

1. 在 Windows 安装 VS Code。
2. 安装扩展：**Remote - SSH**。
3. 点击左下角蓝色图标 `><`，选择 `Connect to Host...`，输入 `ssh 用户名@IP` 连接到你的 Ubuntu。
4. **后续所有插件必须安装在远程端（SSH: <你的服务器名>）下**。

#### 2. VS Code 插件配置（远程侧）
在远程连接的状态下，安装以下插件：

- **Verilog-HDL/SystemVerilog**: 用于语法高亮。
- **CTags Support**: 用于代码定义跳转。
  - *配置提示*：在设置中将 `Include Path` 指向你克隆仓库的 `vsrc` 绝对路径。

#### 3. 波形查看：Windows 版 GTKWave (核心改动)
教程提到由于你不用 Linux 图形界面，波形文件（`.fst` 或 `.vcd`）应在 Windows 上查看：

1. **下载**：在 Windows 下载并解压教程提供的 GTKWave Windows版。
2. **工作流**：
  - 在 VS Code 终端（已连接 SSH）执行 `make` 跑仿真，生成波形文件。
  - 使用 VS Code 的文件浏览器，右键点击生成的波形文件，选择 **Download** 下载到 Windows 本地。
  - 用 Windows 上的 `gtkwave.exe` 打开该文件即可。

---

### 第三阶段：针对 Vivado 的特别规划
由于 Vivado 的图形界面（GUI）在远程 SSH 下体验极差（即便用 X11 转发也很卡）：

- **建议方案**：在 **Windows 本地**安装 Vivado 2018.3。
- **流程**：平时在 Ubuntu 上进行 Verilator 仿真调试（这是实验的主要部分）。只有当需要进行“综合”或“上板”时，将代码拷贝回 Windows，用本地的 Vivado 打开项目进行操作。

---

### 总结：你的专属操作流

1. **写代码**：在 Windows VS Code 里直接改 Ubuntu 上的文件。
2. **跑仿真**：在 VS Code 下方的集成终端里输入命令。
3. **调波形**：仿真报错后，通过 VS Code 把波形文件拖回 Windows 桌面，用本地 GTKWave 观察。
4. **硬件实验**：Verilator 跑通后，代码同步回 Windows 本地，用本地 Vivado 烧录。

---

*Exported from [Gemini Voyager](https://github.com/Nagi-ovo/gemini-voyager)*  
*Generated on March 17, 2026 at 12:28 AM*