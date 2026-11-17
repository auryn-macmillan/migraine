/-
Bridge executable: runs the pinned Verity dependency's compiler driver
so `lake exe verity-compiler` works from this package. (Lake resolves an
exe's root module inside the declaring package, and the dep's own
entry-point `main` cannot be re-declared alongside ours, so we call its
driver `Compiler.Main.run` directly — exactly what the dep's `main`
forwards to.)
-/
import Compiler.MainDriver

unsafe def main (args : List String) : IO Unit :=
  Compiler.Main.run args