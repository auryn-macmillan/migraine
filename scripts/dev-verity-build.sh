#!/usr/bin/env bash
# Fast iteration: copy migraine verity sources into the verity overlay and build a target.
set -u
export PATH="$HOME/.elan/bin:$PATH"
SRC=/home/dev/migraine/verity
DST=/home/dev/verity-upstream
mkdir -p "$DST/Contracts/Migraine/Proofs"
cp "$SRC/Contracts/Migraine.lean" "$DST/Contracts/"
for f in "$SRC"/Contracts/Migraine/*.lean; do cp "$f" "$DST/Contracts/Migraine/"; done
for f in "$SRC"/Contracts/Migraine/Proofs/*.lean; do cp "$f" "$DST/Contracts/Migraine/Proofs/"; done
cd "$DST" || exit 1
TARGET="${1:-Contracts.Migraine.Proofs.System}"
lake build "$TARGET" 2>&1 | grep -vE "^info:|^✔" | head -"${2:-60}"
echo "EXIT=${PIPESTATUS[0]}"