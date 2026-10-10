#!/usr/bin/env bash
#
# Overlay the FixedRateRedeemer Verity sources into a Verity checkout and
# register the new contract with the build and the compiler.
#
# Usage: scripts/ci-verity.sh <path-to-verity-checkout>
#
# The script is idempotent: running it twice is safe.

set -euo pipefail

VERITY_DIR="${1:?usage: ci-verity.sh <path-to-verity-checkout>}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ ! -f "$VERITY_DIR/lakefile.lean" ]]; then
  echo "error: '$VERITY_DIR' does not look like a Verity checkout" >&2
  exit 1
fi

# 1. Copy the contract, spec, invariants, proofs and module re-export.
rm -rf "$VERITY_DIR/Contracts/FixedRateRedeemer"
cp -r "$REPO_ROOT/verity/Contracts/FixedRateRedeemer" "$VERITY_DIR/Contracts/"
cp "$REPO_ROOT/verity/Contracts/FixedRateRedeemer.lean" "$VERITY_DIR/Contracts/"

# 2. Register the module with the build + compiler (idempotent string edits).
python3 - "$VERITY_DIR" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1])

def insert_after(path: Path, anchor: str, addition: str) -> None:
    text = path.read_text()
    if addition.strip() in text:
        return
    if anchor not in text:
        raise SystemExit(f"anchor not found in {path}: {anchor!r}")
    text = text.replace(anchor, anchor + "\n" + addition, 1)
    path.write_text(text)
    print(f"registered in {path}")

# lakefile.lean: add the library glob.
insert_after(
    root / "lakefile.lean",
    "    .andSubmodules `Contracts.Ledger,",
    "    .andSubmodules `Contracts.FixedRateRedeemer,",
)

# Contracts.lean: import the module into the umbrella.
insert_after(
    root / "Contracts.lean",
    "import Contracts.Ledger",
    "import Contracts.FixedRateRedeemer",
)

# Contracts/Specs.lean: import + register the generated CompilationModel.
specs = root / "Contracts" / "Specs.lean"
insert_after(specs, "import Contracts.Ledger", "import Contracts.FixedRateRedeemer")
insert_after(specs, "  Contracts.Ledger.spec,", "  Contracts.FixedRateRedeemer.spec,")
PY

echo "FixedRateRedeemer overlaid into $VERITY_DIR"
