/-
  State invariants for the `Migraine` reference model.
-/

import Verity.Specs.Common

namespace Contracts.Migraine.Invariants

open Verity

/-- Basic well-formedness: the addresses in the context are non-zero. -/
structure WellFormedState (s : ContractState) : Prop where
  sender_nonzero : s.sender ≠ 0
  contract_nonzero : s.thisAddress ≠ 0

end Contracts.Migraine.Invariants
