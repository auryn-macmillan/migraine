#!/usr/bin/env bash
#
# Build and gate the Migraine Verity proofs.
#
# `verity/` is a self-contained Lake package: it pins Verity as a git
# dependency (see verity/lakefile.lean), so there is no fork, no
# checkout overlay, and no in-tree registration. To upgrade Verity,
# bump the pin and rebuild — CI must stay green before the bump lands.
#
# Usage: scripts/ci-verity.sh
#
# The script is idempotent: running it twice is safe.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG="$REPO_ROOT/verity"

cd "$PKG"

# 1. Resolve the pinned Verity (and its transitive pins).
lake update

# 2. Build the model, spec, invariants and the full proof tree.
lake build Migraine.Proofs.Correctness
lake build Migraine

# 3. Axiom gate: every redeem-path theorem must rest only on Lean's
#    standard axioms. Any sorryAx / native-decide leak fails the build.
lake build Migraine.Proofs.AxiomCheck 2>&1 | tee axiomcheck.log
if grep -E "depends on axioms" axiomcheck.log | grep -E "sorryAx|natLitAxiom|ofReduceBool|ofReduceNat"; then
  echo "::error::Axiom leak: proofs depend on a non-standard axiom" >&2
  exit 1
fi
echo "Axiom gate clean."

# Tactic-position sorry/admit only (prose mentions in comments are fine;
# the axiom gate above catches any real sorry via sorryAx anyway).
if grep -rnE '(^|[^A-Za-z0-9_.])(by[[:space:]]+|exact[[:space:]]+|·[[:space:]]+|;\s*|:\s*|sorryAx)(sorry|admit)([^A-Za-z0-9_]|$)' Migraine/; then
  echo "::error::Found sorry/admit in the Migraine proofs" >&2
  exit 1
fi
echo "No sorry/admit found."

# 4. Compile the model to Yul via the pinned Verity's compiler
#    (bridge exe in lakefile.lean, rooted at the dep's Compiler.Main).
printf 'Migraine\n' > migraine.manifest
lake exe verity-compiler --manifest migraine.manifest -o artifacts/yul
test -f artifacts/yul/Migraine.yul
echo "Emitted artifacts/yul/Migraine.yul"