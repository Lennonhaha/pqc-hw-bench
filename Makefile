# pqc-hw-bench Makefile — 标准化命令入口
# 用法: make cpu / make fpga / make report / make verify / make all

PY    = python
PIP   = pip

.PHONY: cpu fpga analyze report verify all setup clean

## 环境准备: 安装 Python 依赖
setup:
	$(PIP) install -r requirements.txt

## CPU 软件基准 (liboqs speed) — 单算法示例
cpu:
	$(PY) software/bench_sw.py --alg ML-KEM-768 --duration 3

## CPU 全量基准 (全部 KEM + SIG)
cpu-all:
	$(PY) software/bench_sw.py --all --duration 3

## FPGA 综合/实现/比特流 (需 Vivado, 在 hardware/ 下执行)
fpga:
	cd hardware && vivado -mode batch -source scripts/build.tcl

## 数据分析: 汇总表 + 图表
analyze:
	$(PY) scripts/analyze.py --summary

## 报告生成 (Markdown)
report: analyze
	$(PY) scripts/report.py

## 编码/格式校验
verify:
	$(PY) scripts/verify.py

## 全流程
all: cpu analyze report

## 清理生成物 (保留 results/raw 数据)
clean:
	rm -rf hardware/project
	rm -rf logs
	find . -name __pycache__ -type d -exec rm -rf {} + 2>/dev/null || true
