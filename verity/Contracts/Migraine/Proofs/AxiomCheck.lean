import Contracts.Migraine.Proofs.RedeemTo
import Contracts.Migraine.Proofs.Basic

-- Axiom hygiene for the redeem-path proofs. Every theorem must rest only on
-- the standard three (propext, Classical.choice, Quot.sound) — no sorry, no
-- custom axioms, no native_decide. CI additionally greps the build log for
-- `sorryAx` and rejects any `axiom` declaration under Contracts/Migraine/.

#print axioms Contracts.Migraine.Proofs.RedeemTo.chain_shape
#print axioms Contracts.Migraine.Proofs.RedeemTo.redeemTo_success_run
#print axioms Contracts.Migraine.Proofs.RedeemTo.redeem_eq_redeemTo_self
#print axioms Contracts.Migraine.Proofs.RedeemTo.no_custody
#print axioms Contracts.Migraine.Proofs.RedeemTo.other_slot_unchanged
#print axioms Contracts.Migraine.Proofs.RedeemTo.preserves_balB_sum
#print axioms Contracts.Migraine.Proofs.RedeemTo.preserves_balA_sum
#print axioms Contracts.Migraine.Proofs.RedeemTo.preserves_config

#print axioms Contracts.Migraine.Proofs.redeem_conserves_inventory
#print axioms Contracts.Migraine.Proofs.inventory_never_increases
#print axioms Contracts.Migraine.Proofs.redeemed_monotone