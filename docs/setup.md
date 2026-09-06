# 环境搭建 (setup.md)

版本: v0.1 (2026-09-06)
平台: Windows 11 (x64) — 本机实测；Linux/macOS 步骤类似

## 1. 前置工具

| 工具 | 版本 | 安装 |
|---|---|---|
| git | 2.47+ | scoop install git |
| cmake | 4.4+ | scoop install cmake |
| ninja | 1.13+ | scoop install ninja |
| gcc (MinGW) | 15.x | scoop install gcc |
| Python | 3.11+ | scoop install python |
| Vivado | 2021.1+ | 官网（FPGA 综合，仅硬件阶段需要） |

验证：
```powershell
cmake --version; ninja --version; gcc --version; python --version
```

## 2. liboqs 编译（CPU 基线）

```powershell
# 克隆（QMTAP 挡 443 时用 SSH -p 22）
$env:GIT_SSH_COMMAND = "ssh -p 22 -o StrictHostKeyChecking=no"
git clone --depth 1 git@github.com:open-quantum-safe/liboqs.git D:\FIBEMATE\liboqs-src

# 配置（全量含 ML-KEM + ML-DSA，编译 tests 以得 speed_kem/speed_sig）
cmake -S D:\FIBEMATE\liboqs-src -B D:\FIBEMATE\liboqs-build -G Ninja `
      -DCMAKE_BUILD_TYPE=Release -DOQS_BUILD_TESTS=ON -DCMAKE_C_COMPILER=gcc

# 编译（约 5-10 分钟）
cmake --build D:\FIBEMATE\liboqs-build --config Release
```

产物：`tests/speed_kem.exe`、`tests/speed_sig.exe`

本机实测版本：liboqs 0.16.0，CPU exts: ADX AES AVX AVX2 BMI1 BMI2 PCLMULQDQ POPCNT

## 3. Python 分析栈

```powershell
pip install pandas numpy matplotlib jsonschema pyserial
```

## 4. 网络注意事项（本机）

- QMTAP 虚拟网卡阻断 443 端口（HTTPS/SSH-443 均不通）
- GitHub 操作必须走 **SSH -p 22**：`$env:GIT_SSH_COMMAND = "ssh -p 22 -o StrictHostKeyChecking=no"`
- ~/.ssh/config 中 github.com 被映射到 443，须用 -p 22 显式覆盖

## 5. FPGA 阶段（待硬件就绪）

- Vivado 2021.1，器件 xc7a35tfgg484-2 (Artix-7 35T)
- 综合脚本：`hardware/scripts/build.tcl`（注意原脚本内 E:\fpga\fibemate 绝对路径需改相对）
- 板级通信：UART 115200 8N1（顶层已有 uart_tx 通道）
