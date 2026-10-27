module AgcKernel

import Data.Fin
import Data.Vect

%default total

||| 3-valued balanced ternary trit (`-1`, `0`, `+1`) for quantized NANDIFY.
public export
data Trit : Type where
  TNeg  : Trit
  TZero : Trit
  TPos  : Trit

||| Kleene 3-valued AND (`+AND=1`).
public export
kleeneAnd : Trit -> Trit -> Trit
kleeneAnd TNeg  _     = TNeg
kleeneAnd _     TNeg  = TNeg
kleeneAnd TPos  TPos  = TPos
kleeneAnd _     _     = TZero

||| Universal Kleene 3-valued NAND (`~NAND=-1`).
public export
kleeneNand : Trit -> Trit -> Trit
kleeneNand a b = case kleeneAnd a b of
  TPos  => TNeg
  TNeg  => TPos
  TZero => TZero

||| Proof that Kleene NAND on two positive trits yields TNeg (`-1`).
public export
nandPosPosIsNeg : kleeneNand TPos TPos = TNeg
nandPosPosIsNeg = Refl

||| Linear Vector Accumulator (VAC) token (`1` multiplicity in QTT).
||| A FINDVAC interpretive job must consume (`1`) and return (`1`) its VacToken
||| to `endJob`, making Apollo 11's 1201 VAC-leak alarm impossible in well-typed code.
public export
data VacToken : (slot : Fin 5) -> Type where
  MkVac : (slot : Fin 5) -> VacToken slot

||| Consume a linear VacToken when an interpretive FINDVAC job completes (`ENDJOB`).
public export
releaseVac : (1 _ : VacToken slot) -> Fin 5
releaseVac (MkVac s) = s

||| Bounded WAITLIST task queue (`Fin 9` max capacity per Luminary099/WAITLIST.agc).
public export
record WaitlistEntry where
  constructor MkWaitEntry
  deltaCs : Nat
  cad2    : Bits16
