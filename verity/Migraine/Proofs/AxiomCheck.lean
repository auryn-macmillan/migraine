import Migraine.Proofs.RedeemTo
import Migraine.Proofs.Basic

-- Axiom hygiene for the redeem-path proofs. Every theorem must rest only on
-- the standard three (propext, Classical.choice, Quot.sound) — no sorry, no
-- custom axioms, no native_decide. CI additionally greps the build log for
-- `sorryAx` and rejects any `axiom` declaration under Migraine/.

#print axioms Migraine.Proofs.RedeemTo.chain_shape
#print axioms Migraine.Proofs.RedeemTo.redeemTo_success_run
#print axioms Migraine.Proofs.RedeemTo.redeemTo_success_run_max
#print axioms Migraine.Proofs.RedeemTo.redeem_eq_redeemTo_self
#print axioms Migraine.Proofs.RedeemTo.no_custody
#print axioms Migraine.Proofs.RedeemTo.other_slot_unchanged
#print axioms Migraine.Proofs.RedeemTo.preserves_balB_sum
#print axioms Migraine.Proofs.RedeemTo.preserves_balA_sum
#print axioms Migraine.Proofs.RedeemTo.preserves_config

#print axioms Migraine.Proofs.redeem_conserves_inventory
#print axioms Migraine.Proofs.inventory_never_increases
#print axioms Migraine.Proofs.redeemed_monotone