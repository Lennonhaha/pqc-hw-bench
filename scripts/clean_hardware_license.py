#!/usr/bin/env python3
"""Clean residual 'MIT License' / 'Copyright 2026 FIBEMATE' lines left inside header banners
after re-tagging. Header banners vary; strategy: within first 15 lines, drop lines that are
exactly '// MIT License', '// Copyright 2026 FIBEMATE', or comment-only variants; also drop
duplicate '// SPDX' lines. Keep banner structure."""
import os

HW = r'D:\FIBEMATE\pqc-hw-bench\hardware'
DROPS = ('mit license', 'copyright 2026 fibemate', 'spdx-license-identifier: mit')

def clean(path):
    with open(path, 'r', encoding='utf-8', errors='replace') as f:
        lines = f.read().split('\n')
    changed = False
    out = []
    for i, ln in enumerate(lines):
        low = ln.lower().strip()
        if i < 18 and any(d in low for d in DROPS) and ('//' in ln or '#' in ln):
            changed = True
            continue  # drop
        out.append(ln)
    # collapse 3+ blank lines to 2
    res = []
    blanks = 0
    for ln in out:
        if ln.strip() == '':
            blanks += 1
            if blanks <= 2:
                res.append(ln)
        else:
            blanks = 0
            res.append(ln)
    text = '\n'.join(res)
    if changed or text != '\n'.join(out):
        with open(path, 'w', encoding='utf-8', newline='\n') as f:
            f.write(text)
        return True
    return False

count = 0
for root, dirs, files in os.walk(HW):
    for fn in sorted(files):
        p = os.path.join(root, fn)
        if os.path.splitext(fn)[1].lower() in ('.v', '.vh', '.tcl', '.xdc'):
            if clean(p):
                count += 1
                print(f'  cleaned: {os.path.relpath(p, HW)}')
print(f'Cleaned {count} files')
