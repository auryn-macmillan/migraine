import Lake
open Lake DSL

/--
Self-contained Verity formalization of the Migraine contract.

Depends on Verity as a pinned git package — no fork, no overlay, no
in-tree registration. Bump the pin to upgrade Verity; the proof tree
must then rebuild green against the new core before the bump lands.
-/
package «migraine-verity» where
  version := v!"1.0.0"

require verity from git
  "https://github.com/lfglabs-dev/verity.git"@"ac82752cc"

/--
The Migraine model, spec, invariants and proofs. The umbrella module
`Migraine` re-exports the proof tree, so the default target pulls in
everything including `Migraine.Proofs.AxiomCheck`.

Note: deliberately *not* namespaced under `Contracts` — that is Verity's
own example library, and same-named modules across packages confuse
Lake's module resolution.
-/
@[default_target]
lean_lib «Migraine» where
  globs := #[
    .one `Migraine,
    .andSubmodules `Migraine
  ]

/--
Bridge to the pinned Verity's Yul compiler: `lake exe verity-compiler`
builds and runs the dep's `Compiler.Main` from this package (Lake does
not expose dependency executables directly).
-/
lean_exe «verity-compiler» where
  root := `CompilerMain
  supportInterpreter := true