#!/usr/bin/env bash
# Fast iteration: build a target in the self-contained verity/ package.
set -u
export PATH="$HOME/.elan/bin:$PATH"
cd /home/dev/migraine/verity || exit 1
TARGET="${1:-Contracts.Migraine}"
lake build "$TARGET" 2>&1 | grep -vE "^info:|^✔" | head -"${2:-60}"
echo "EXIT=${PIPESTATUS[0]}"