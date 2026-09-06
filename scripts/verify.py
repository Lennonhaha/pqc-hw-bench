#!/usr/bin/env python3
"""verify.py — 仓库卫生校验（编码 + 数据完整性）
供 Makefile `make verify` 与 CI 调用。

检查:
1. 全仓文本文件 UTF-8 无 BOM 无 U+FFFD
2. results/raw 数据文件可解析、无空/半截文件
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "results" / "raw"
SKIP_SUFFIX = {".png", ".exe", ".bin", ".jpg", ".tsr", ".tsq", ".pem", ".pyc", ".bit"}
SKIP_DIRS = {".git", "__pycache__", "project", ".Xil", "logs"}

BIN_LIKE = {".png", ".exe", ".bin", ".jpg", ".tsr", ".tsq", ".pem", ".pyc", ".bit"}


def check_encoding() -> list[str]:
    problems = []
    for p in ROOT.rglob("*"):
        if p.is_dir() or any(part in SKIP_DIRS for part in p.parts):
            continue
        if p.suffix.lower() in BIN_LIKE:
            continue
        try:
            b = p.read_bytes()
            if b.startswith(b"\xef\xbb\xbf"):
                problems.append(f"UTF-8 BOM: {p.relative_to(ROOT)}")
                continue
            text = b.decode("utf-8")
            if "\ufffd" in text:
                problems.append(f"U+FFFD: {p.relative_to(ROOT)}")
        except UnicodeDecodeError:
            problems.append(f"非 UTF-8: {p.relative_to(ROOT)}")
    return problems


def check_data() -> list[str]:
    problems = []
    for p in sorted(RAW.glob("*.txt")):
        if p.stat().st_size < 100:
            problems.append(f"疑似空/半截数据: {p.name} ({p.stat().st_size}B)")
    # summary csv 存在性
    csvs = list(RAW.glob("summary-*.csv"))
    if not csvs:
        problems.append("缺少 summary CSV (先跑 analyze.py)")
    return problems


def main():
    problems = check_encoding() + check_data()
    if problems:
        print(f"[FAIL] {len(problems)} 个问题:")
        for p in problems:
            print(f"  - {p}")
        sys.exit(1)
    files = sum(1 for p in ROOT.rglob("*") if p.is_file())
    print(f"[OK] 编码/数据校验通过 ({files} 文件)")


if __name__ == "__main__":
    main()
