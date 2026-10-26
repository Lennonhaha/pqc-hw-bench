# pqc-hw-bench 许可证地图 / License map

本仓库**按目录分层许可**，不存在单一许可证。GitHub 首页显示的许可证（MIT）来自根 `LICENSE`，
它覆盖 `software/` 与 `scripts/` 的默认情形；下表是权威概览，每一行都对应仓库内的一份许可证全文。

| 路径 | 许可证 | 全文位置 |
|---|---|---|
| `software/`、`scripts/`（Python 与构建脚本） | MIT | [`LICENSE`](./LICENSE)、[`software/LICENSE`](./software/LICENSE) |
| `hardware/`（Verilog RTL、约束、仿真） | CERN-OHL-P-2.0 | [`hardware/LICENSE`](./hardware/LICENSE) |
| `docs/`、`reports/`（文档、报告、数据） | CC BY-SA 4.0 | [`docs/LICENSE`](./docs/LICENSE) |

## 为什么根 LICENSE 是 MIT

GitHub 只读取仓库根目录的许可证文件来生成首页许可证标识。此前根 `LICENSE` 是一份说明性文字
（不是许可证正文），因此本仓库长期显示为 `NOASSERTION` —— 在采购与合规流程里等价于"未授权"。

现在根 `LICENSE` 放 MIT 全文，作为**软件与脚本部分的默认许可**；硬件与文档的许可由各自目录下的
全文声明，并集中在本表指向。三份许可证全文都完整随仓库分发，不依赖外链
（CERN-OHL-P-2.0 §3.1 要求分发时随附许可证副本）。

## 资产来源声明

`hardware/` 下的 Verilog RTL 源自 FIBEMATE 项目
（<https://github.com/Lennonhaha/fibemate> 的 `fpga/rtl/`），作者与版权人均为本仓库作者。
提取入本仓库时由同一版权人授权为 CERN-OHL-P-2.0，逐文件追溯见
[`docs/provenance.md`](./docs/provenance.md)。

Copyright © 2026 Liu Tianhe (Lennonhaha)
