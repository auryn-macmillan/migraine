# Migraine Lean proofs — resume note (2026-10-24, ~02:40 EDT)

## Where we are
Resumed the Migraine formal-proof work (repo `/home/dev/migraine`, overlay mirror
`/home/dev/verity-upstream/Contracts/Migraine`). Goal: fill in the `redeemTo`
success-path theorems that `Proofs/System.lean`'s docstring promises but doesn't yet
prove.

**Already proven & committed-to-file in `Proofs/System.lean` (4 theorems):**
`previewRedeem_run`, `previewRedeem_preserves_state`, `deploy_meets_spec`,
`redeemTo_revert_state_unchanged`. Baseline `Contracts.Migraine.Proofs.System` builds.

**In progress:** one scratch theorem `transferFrom_unfold_other` — the linchpin exact
run of the inlined `transferFrom` (parameterized over balance/allowance slots). It
mirrors `Contracts.ERC20.Proofs.Basic.transfer_unfold_other` and is the foundation for
all the projection theorems (`redeemTo_success_rate`, `redeemTo_success_effects`,
`redeemTo_no_custody`, `redeemTo_custody_zero`, `redeemTo_preserves_bal{A,B}_sum`,
`redeemTo_preserves_config`, `redeemTo_preserves_ValidConfig`).

**Current scratch file:** `/home/dev/verity-upstream/Contracts/Migraine/Proofs/Scratch.lean`
(also snapshotted to `/home/dev/migraine/transferFrom_scratch_snapshot.lean`, 46 lines).
It imports System + Automation + Math + ListSum and opens the needed namespaces.

## Build/verify command
```
cd /home/dev/verity-upstream && export PATH="$HOME/.elan/bin:$PATH" \
  && lake build Contracts.Migraine.Proofs.Scratch 2>&1 | grep -A 20 "Scratch.lean:3"
```
(Use target `Contracts.Migraine.Proofs.Scratch`. Do NOT use the migraine repo's
`scripts/dev-verity-build.sh` for scratch — it only knows the System target. The
scratch file is NOT in the lakefile's Contracts.Migraine lib source set automatically;
it builds because it lives under `Contracts/Migraine/Proofs/` which the Migraine lib
pulls in transitively? — actually it builds as its own target; lakefile auto-discovers.)

## Progress on `transferFrom_unfold_other` — what the simp set already achieves
The `verity_unfold transferFrom` + `simp only [...]` now reduces the goal all the way
to the **balance-check `if`**, but that final `if` does NOT close. Current state of the
goal (from last build):
- Allowance check fully resolved: `h_allow`, `h_not_max`, `h_beq_false` all fire; the
  `if (allowance != MAX_UINT256)` branch reduced to the `setMapping2` (allowance debit) path.
- Balance check stuck at:
  `if s.storageWords (StorageKey.map balSlot.slot srcAddr) ≥ amount then …`
  with hypothesis `h_bal : s.storageMap balSlot.slot srcAddr ≥ amount`.

The mismatch: the goal reads `s.storageWords (StorageKey.map …)` but `h_bal` is stated
with `s.storageMap …`. Need to bridge `storageMap` ↔ `storageWords (StorageKey.map …)`.

## KEY DISCOVERY blocking the last step — Bool `>=` vs Prop `≥`
This is the crux, verify before retrying:
- The model's `require (fromBalance >= amount)` (System.lean:146) takes a **Bool**
  (`Verity.require : Bool → String → Contract Unit`, Core.lean:2735). So `>=` in the
  model is **Bool**.
- But `h_bal : s.storageMap … ≥ amount` and `uint256_ge_val_le (h : a ≥ b)` use **Prop** `≥`.
- So the goal's `if … ≥ amount` (from require, Bool) and `h_bal` (Prop `≥`) are
  **different types** — that's why `ite_true` won't fire.
- Reference `transfer_unfold_other` (ERC20/Proofs/Basic.lean:128-152) closes its
  balance check with `h_balance` + `decide_eq_true_eq` + `ite_true`. Its balance read
  is on the ORIGINAL state (no prior write), so its goal condition is literally
  `s.storageMap 2 s.sender ≥ amount` = `h_balance`.
- In our `transferFrom`, the balance read happens AFTER the allowance `setMapping2`, so
  the goal condition is `s.storageWords (StorageKey.map …) ≥ amount` (reduced through
  the writeMap2), NOT matching `h_bal` syntactically.

**Likely fix directions (try in order):**
1. Make the goal condition syntactically `s.storageMap balSlot.slot srcAddr ≥ amount`
   to match `h_bal`. The `@[simp]` lens law `storageMap_writeMap2`
   (`(s.writeMap2 slot k1 k2 v).storageMap = s.storageMap`, Core.lean:1430) is the
   right tool BUT it only matches the un-expanded `s.writeMap2 …` form; after
   `verity_unfold`/simp the state is already the expanded record
   `{ storageWords := fun k => if k = StorageKey.map2 … then … else s.storageWords k, … }`,
   so `storageMap_writeMap2` does NOT match. Tried it — no effect.
2. Keep the storageWords reduction (needs `StorageKey.map_ne_map2` Core.lean:368-370 +
   `ContractState.storageMap` to unfold) AND rewrite `h_bal` into the same storageWords
   form via `ContractState.storageMap`. **BUT** this still didn't fire `ite_true`
   even when both sides matched — strongly suggests the goal `if` condition is **Bool**
   `>=` while `h_bal` is **Prop** `≥`. Need a Bool↔Prop bridge:
   - `Bool.not_eq_true' : ((!b) = true) = (b = false)` — already used for the `!=`/allowance check.
   - Look for a `ge`/`>=` Bool bridge analogous to `Int256.sge_iff`
     (`sge a b = true ↔ (a:Int) ≥ (b:Int)`, Int256.lean:419). Check whether Uint256
     has a Bool `>=`/`ge` and its `= true ↔ Prop ≥` lemma. If none, may need to state
     `h_bal` with the Bool comparison, or add `rw [decide_eq_true_eq]`-style handling.
   - The reference uses Prop `≥` in `h_balance` and it works, so a bridge exists there
     via `decide_eq_true_eq`; the difference is our condition is post-write. Reconcile
     by NOT unfolding storageMap (keep `s.storageMap …`), which requires the read to
     reduce to `s.storageMap …` not `s.storageWords …`.

## Established facts / API (verified this session)
- `transferFrom` unfold simp set (validated by parent's `Probe.lean`):
  `[transferFrom, contractAddress, getMapping, getMapping2, setMapping, setMapping2,
    ContractState.readMap, ContractState.readMap2, ContractState.writeMap,
    ContractState.writeMap2, requireSomeUint, Verity.require, Verity.pure, Verity.bind,
    Bind.bind, Pure.pure, Contract.run, h_allow, h_bal, h_ne, h_not_max, beq_iff_eq,
    decide_eq_true_eq, ite_true, ite_false, h_safe, HAdd.hAdd]`
  + `verity_unfold transferFrom` first.
- `contractAddress` must be qualified BOTH `Contracts.contractAddress` and
  `Verity.contractAddress` (goal shows `Contracts.contractAddress`).
- `!=` is `bne` = `!(a == b)`; bridge to `≠` needs `Bool.not_eq_true'`
  (` ((!b) = true) = (b = false)`), NOT `beNe_iff` (that's for `≠` Prop and is not in scope).
  Also need `beq_false_of_ne h : (a == b) = false` (derive `h_beq_false` from `h_not_max`).
- `h_balance' := uint256_ge_val_le h_bal` and `h_safe := safeAdd_some dstAddr amount h_no_overflow`
  are needed (from reference).
- State after the allowance write: `writeMap2` then two `.writeMap` chained; the record
  base must be wrapped so `.writeMap` binds to it:
  `{ ((s.writeMap2 …)).writeMap … .writeMap … with knownAddresses := … }`
  (the extra outer paren + `.writeMap` on the SAME line as the closing `)` is required
  by the parser; method-chain `.writeMap` on its own line fails to parse).
- `knownAddresses`: only `setMapping` (single) overrides it to insert the key;
  `setMapping2`/`writeMap2` leave it unchanged. So final knownAddresses inserts srcAddr
  and dstAddr at `balSlot.slot` only:
  `if slotIdx == balSlot.slot then ((s.knownAddresses slotIdx).insert srcAddr).insert dstAddr else s.knownAddresses slotIdx`.

## Model facts (System.lean)
- Slots: config 0-4 (tokenA,tokenB,wallet,num,den); ledger 5=balA,6=allowA,7=balB,8=allowB.
- `transferFrom balSlot allowSlot srcAddr dstAddr amount`: spender = contractAddress;
  check allowance (`>=`, debit unless `== MAX_UINT256`), check balance (`>=`), self-transfer
  no-op, else debit src + credit dst (checked add).
- `redeemTo amountA recipient`: reads config, requires (ZeroAmount, MulDiv via
  requireSomeUint, ZeroOutput, 5-way InvalidRecipient), emitEvent Redeemed, then
  `transferFrom balASlot allowASlot sender wallet amountA` then
  `transferFrom balBSlot allowBSlot wallet recipient amountB`, returns amountB.

## Tooling gotcha (also in Hermes memory)
`read_file` on `.lean` files serves STALE deduped content from an earlier read in a
prior session — it lies ("File unchanged since last read"). ALWAYS use terminal
`cat -n`/`sed`/`grep` for ground truth on these files.

## Next concrete step
`transferFrom_unfold_other` now BUILDS (verified EXIT=0, `lake build Contracts.Migraine.Proofs.Scratch`).
The remaining work is deriving the 8 projection theorems from it, then integrating into
`Proofs/System.lean` and updating its docstring coverage map. See "Projection theorems" below.

## RESOLVED: how transferFrom_unfold_other was closed (2026-10-24)
The final working proof (Scratch.lean lines 35-54). Two insights beyond the reference:
1. **Post-writeMap2 balance/allowance reads need a storageWords bridge.** After the
   allowance `setMapping2`, the subsequent balance read is on the modified state, which
   `simp` renders as `s.storageWords (StorageKey.map balSlot.slot srcAddr)` — NOT the
   `s.storageMap …` form of the hypotheses. So `h_bal`/`h_safe` (stated with
   `s.storageMap …`) don't match. Fix: add `ContractState.storageMap` + `StorageKey.map_ne_map2`
   to the simp set to push the read to storageWords form, AND add defeq-bridged copies:
       have h_bal' : s.storageWords (StorageKey.map balSlot.slot srcAddr) ≥ amount := h_bal
       have h_safe' : safeAdd (s.storageWords (StorageKey.map balSlot.slot dstAddr)) amount =
           some (s.storageWords (StorageKey.map balSlot.slot dstAddr) + amount) := h_safe
   (Lean accepts these because `s.storageMap slot key` is defeq to
   `s.storageWords (StorageKey.map slot key)`.) Then include `h_bal'`/`h_safe'` in simp.
   `storageMap_writeMap2` does NOT help: after unfold the state is the expanded record
   `{ storageWords := … }`, not syntactically `s.writeMap2 …`, so that lemma doesn't match.
2. **Final state-equality closes with the reference tail:** `congr 1; congr 1; funext slotIdx; split <;> simp [*]`.
   LHS/RHS differ only in the nested-if structure of `knownAddresses` and defeq
   `add` vs `Core.Uint256.add`.

Full validated simp set (in addition to the base list from before):
`ContractState.storageMap, StorageKey.map_ne_map2, h_bal', h_safe'` — and drop
`storageMap_writeMap2`. Keep `bne, Bool.not_eq_true'` for the `!=`/allowance check,
`decide_eq_true_eq, ite_true, ite_false` for the require checks.