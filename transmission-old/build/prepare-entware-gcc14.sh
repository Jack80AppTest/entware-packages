#!/bin/sh
set -eu

ROOT="${1:-.}"
GETTEXT="$ROOT/package/libs/gettext-full/Makefile"
GLIBC="$ROOT/toolchain/glibc/common.mk"

python3 - "$GETTEXT" "$GLIBC" <<'PY'
from pathlib import Path
import sys

gettext = Path(sys.argv[1])
glibc = Path(sys.argv[2])

s = gettext.read_text()
old = '#TARGET_CFLAGS += -std=gnu23'
new = 'TARGET_CFLAGS += -std=gnu23'
if old not in s and new not in s:
    raise SystemExit(f'expected gettext marker not found in {gettext}')
if old in s:
    s = s.replace(old, new, 1)
    gettext.write_text(s)

s = glibc.read_text()
old = 'CFLAGS="-O2 $(filter-out -O%,$(call qstrip,$(TARGET_CFLAGS)))" \\'
new = 'CFLAGS="-O2 -fcommon $(filter-out -O%,$(call qstrip,$(TARGET_CFLAGS)))" \\'
if old not in s and new not in s:
    raise SystemExit(f'expected glibc CFLAGS marker not found in {glibc}')
if old in s:
    s = s.replace(old, new, 1)
    glibc.write_text(s)
PY
