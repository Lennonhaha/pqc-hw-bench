#!/usr/bin/env python3
"""Re-tag SPDX headers in pqc-hw-bench/hardware: MIT FIBEMATE -> CERN-OHL-P-2.0 Liu Tianhe
Author re-licensing of own code. See docs/provenance.md."""
import os, re, sys

HW = r'D:\FIBEMATE\pqc-hw-bench\hardware'
NEW_HEADER = '// Copyright 2026 Liu Tianhe (Lennonhaha)\n// SPDX-License-Identifier: CERN-OHL-P-2.0\n'
NEW_HEADER_TCL = '# Copyright 2026 Liu Tianhe (Lennonhaha)\n# SPDX-License-Identifier: CERN-OHL-P-2.0\n'
NEW_HEADER_XDC = '# Copyright 2026 Liu Tianhe (Lennonhaha)\n# SPDX-License-Identifier: CERN-OHL-P-2.0\n'

def process(path, comment_style):
    with open(path, 'r', encoding='utf-8', errors='replace') as f:
        content = f.read()
    orig = content
    # Remove existing copyright/SPDX header lines at top of file (first comment block)
    lines = content.split('\n')
    out = []
    i = 0
    # skip shebang
    if lines and lines[0].startswith('#!'):
        out.append(lines[0]); i = 1
    # Skip leading comment block lines that are copyright/SPDX (allow banner text before?)
    # Strategy: find first line containing SPDX-License-Identifier; remove it + adjacent copyright lines
    spdx_idx = None
    for j in range(len(lines)):
        if 'SPDX-License-Identifier' in lines[j]:
            spdx_idx = j
            break
    if spdx_idx is not None:
        # remove the SPDX line
        lines.pop(spdx_idx)
        # remove a copyright line within 3 lines above that is a comment
        for k in range(max(0, spdx_idx-3), spdx_idx):
            if k < len(lines) and ('opyright' in lines[k]) and lines[k].strip().startswith(comment_style):
                lines.pop(k)
                break
    # Now prepend new header after shebang (if any) or banner? Prepend at top (after shebang)
    text = '\n'.join(lines).lstrip('\n')
    header = NEW_HEADER if comment_style == '//' else (NEW_HEADER_TCL if comment_style == '#' else NEW_HEADER_XDC)
    if text.startswith('#!'):
        nl = text.index('\n')
        text = text[:nl+1] + header + text[nl+1:]
    else:
        text = header + text
    # ensure single blank line after header where code begins
    text = re.sub(r'(CERN-OHL-P-2\.0\n)\n{2,}', r'\1\n', text)
    if text != orig:
        with open(path, 'w', encoding='utf-8', newline='\n') as f:
            f.write(text)
        return True
    return False

count = 0
for root, dirs, files in os.walk(HW):
    for fn in sorted(files):
        p = os.path.join(root, fn)
        ext = os.path.splitext(fn)[1].lower()
        if ext == '.v':
            if process(p, '//'): count += 1
        elif ext == '.tcl':
            if process(p, '#'): count += 1
        elif ext == '.xdc':
            if process(p, '#'): count += 1
        elif fn == 'zetas.mem':
            continue
        elif ext == '.sv':
            if process(p, '//'): count += 1
print(f'Re-tagged {count} files with CERN-OHL-P-2.0 header')
