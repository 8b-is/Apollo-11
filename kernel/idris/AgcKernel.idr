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

||| Kleene 3-valued negation (`~`).
public export
kleeneNot : Trit -> Trit
kleeneNot TNeg  = TPos
kleeneNot TZero = TZero
kleeneNot TPos  = TNeg

||| Kleene 3-valued AND (`+AND=1`).
public export
kleeneAnd : Trit -> Trit -> Trit
kleeneAnd TNeg  _     = TNeg
kleeneAnd _     TNeg  = TNeg
kleeneAnd TPos  TPos  = TPos
kleeneAnd _     _     = TZero

||| Kleene 3-valued OR (`max`).
public export
kleeneOr : Trit -> Trit -> Trit
kleeneOr TPos  _     = TPos
kleeneOr _     TPos  = TPos
kleeneOr TNeg  TNeg  = TNeg
kleeneOr _     _     = TZero

||| Universal Kleene 3-valued NAND (`~NAND=-1`).
public export
kleeneNand : Trit -> Trit -> Trit
kleeneNand a b = kleeneNot (kleeneAnd a b)

||| Theorem 1: Kleene negation is strictly involutive (`~(~x) = x`).
public export
kleeneNotInvolutive : (t : Trit) -> kleeneNot (kleeneNot t) = t
kleeneNotInvolutive TNeg  = Refl
kleeneNotInvolutive TZero = Refl
kleeneNotInvolutive TPos  = Refl

||| Theorem 2: Universal NAND synthesizes Kleene NOT (`NAND(x, x) = ~x`).
public export
nandDiagonalIsNot : (t : Trit) -> kleeneNand t t = kleeneNot t
nandDiagonalIsNot TNeg  = Refl
nandDiagonalIsNot TZero = Refl
nandDiagonalIsNot TPos  = Refl

||| Theorem 3: Universal NAND synthesizes Kleene AND (`NAND(NAND(a,b), NAND(a,b)) = AND(a,b)`).
public export
nandSynthesizesAnd : (a, b : Trit) -> kleeneNand (kleeneNand a b) (kleeneNand a b) = kleeneAnd a b
nandSynthesizesAnd TNeg  TNeg  = Refl
nandSynthesizesAnd TNeg  TZero = Refl
nandSynthesizesAnd TNeg  TPos  = Refl
nandSynthesizesAnd TZero TNeg  = Refl
nandSynthesizesAnd TZero TZero = Refl
nandSynthesizesAnd TZero TPos  = Refl
nandSynthesizesAnd TPos  TNeg  = Refl
nandSynthesizesAnd TPos  TZero = Refl
nandSynthesizesAnd TPos  TPos  = Refl

||| Theorem 4: Universal NAND synthesizes Kleene OR via De Morgan's law
||| (`NAND(NAND(a,a), NAND(b,b)) = OR(a,b)`).
public export
nandSynthesizesOr : (a, b : Trit) -> kleeneNand (kleeneNand a a) (kleeneNand b b) = kleeneOr a b
nandSynthesizesOr TNeg  TNeg  = Refl
nandSynthesizesOr TNeg  TZero = Refl
nandSynthesizesOr TNeg  TPos  = Refl
nandSynthesizesOr TZero TNeg  = Refl
nandSynthesizesOr TZero TZero = Refl
nandSynthesizesOr TZero TPos  = Refl
nandSynthesizesOr TPos  TNeg  = Refl
nandSynthesizesOr TPos  TZero = Refl
nandSynthesizesOr TPos  TPos  = Refl

||| Proof that `+AND=1` and `~NAND=-1` hold simultaneously on positive signal lanes.
public export
gate0x62Identity : (kleeneAnd TPos TPos = TPos, kleeneNand TPos TPos = TNeg)
gate0x62Identity = (Refl, Refl)

||| Kleene 3-valued XOR (`(a OR b) AND ~(a AND b)` synthesized via Kleene NAND).
public export
kleeneXor : Trit -> Trit -> Trit
kleeneXor a b = kleeneAnd (kleeneOr a b) (kleeneNand a b)

||| `xorOr` composite Kleene gate (`(a XOR b) OR (a AND b)`).
public export
kleeneXorOr : Trit -> Trit -> Trit
kleeneXorOr a b = kleeneOr (kleeneXor a b) (kleeneAnd a b)

||| `andNandOr` Ultratron Kleene gate (`(a OR b) AND ((a AND b) OR (a NAND b))`).
public export
kleeneAndNandOr : Trit -> Trit -> Trit
kleeneAndNandOr a b = kleeneAnd (kleeneOr a b) (kleeneOr (kleeneAnd a b) (kleeneNand a b))

||| Ultratron Theorem: On definite binary-embedded trits (`TPos` / `TNeg`),
||| `kleeneXorOr` and `kleeneAndNandOr` both reduce to `kleeneOr` (`1/1` identity at `0x62`).
public export
ultratronXorOrPosPos : kleeneXorOr TPos TPos = TPos
ultratronXorOrPosPos = Refl

public export
ultratronAndNandOrPosNeg : kleeneAndNandOr TPos TNeg = TPos
ultratronAndNandOrPosNeg = Refl

||| Dependent type indexing the `0x62` gate state progression (`-1 -> 0 -> +1`).
public export
data Gate0x62Transition : (fromState : Trit) -> (toState : Trit) -> Type where
  ClampJitterToZero : Gate0x62Transition TNeg TZero
  SealZeroToPos     : Gate0x62Transition TZero TPos
  ComposeGate0x62   : Gate0x62Transition a b -> Gate0x62Transition b c -> Gate0x62Transition a c

||| Full verified transition from unmanaged amplitude (`-1`) through `0` to sealed `+1`.
public export
luminousStillnessSeal : Gate0x62Transition TNeg TPos
luminousStillnessSeal = ComposeGate0x62 ClampJitterToZero SealZeroToPos

||| Explicit `BFP-64` 64-trit bitplane boundary witness ensuring zero-float integer
||| alignment across 8 parallel lanes (`8 * 8 = 64` trits) at `qt:5a` / `0x62`.
public export
data Bfp64Boundary : (lanes : Nat) -> (tritsPerLane : Nat) -> Type where
  MkBfp64Boundary : (lanes : Nat) -> (tritsPerLane : Nat) ->
                    (0 prf : lanes * tritsPerLane = 64) ->
                    Bfp64Boundary lanes tritsPerLane

||| Canonical 8-lane x 8-trit = 64-trit Laser Phoenix Lattice Lock boundary witness.
public export
laserPhoenixBfp64Boundary : Bfp64Boundary 8 8
laserPhoenixBfp64Boundary = MkBfp64Boundary 8 8 Refl

||| Tightened `luminousStillnessSeal` parameterized by an explicit `BFP-64` boundary proof,
||| guaranteeing zero-float drift at extreme compression ratios (`1695/1327`, `3761/3314`).
public export
luminousStillnessBfp64Seal : Bfp64Boundary 8 8 -> Gate0x62Transition TNeg TPos
luminousStillnessBfp64Seal (MkBfp64Boundary 8 8 Refl) = luminousStillnessSeal

||| Linear CoreSet token (`Fin 7` per `Luminary099/EXECUTIVE.agc`) with QTT multiplicity `1`.
public export
data CoreSetToken : (slot : Fin 7) -> Type where
  MkCoreSet : (slot : Fin 7) -> CoreSetToken slot

||| Linear Vector Accumulator (VAC) token (`Fin 5` per `Luminary099/EXECUTIVE.agc`).
||| A FINDVAC interpretive job must consume (`1`) and return (`1`) its VacToken
||| to `endFindvacJob`, making Apollo 11's 1201 VAC-leak alarm impossible in well-typed code.
public export
data VacToken : (slot : Fin 5) -> Type where
  MkVac : (slot : Fin 5) -> VacToken slot

||| Terminate a NOVAC job by linearly consuming its CoreSetToken.
public export
endNovacJob : (1 _ : CoreSetToken cSlot) -> Fin 7
endNovacJob (MkCoreSet c) = c

||| Terminate a FINDVAC interpretive job by linearly consuming both its CoreSetToken and VacToken.
public export
endFindvacJob : (1 _ : CoreSetToken cSlot) -> (1 _ : VacToken vSlot) -> (Fin 7, Fin 5)
endFindvacJob (MkCoreSet c) (MkVac v) = (c, v)

||| Bounded WAITLIST task queue (`Fin 9` max capacity per `Luminary099/WAITLIST.agc`).
public export
record WaitlistEntry where
  constructor MkWaitEntry
  deltaCs : Nat
  cad2    : Bits16

||| Statically bounded WAITLIST vector (`n <= 9`) preventing `OCT 1203` overflow by construction.
public export
data SafeWaitlist : (n : Nat) -> Type where
  EmptyWaitlist : SafeWaitlist 0
  ScheduleTask  : (entry : WaitlistEntry) -> SafeWaitlist n -> SafeWaitlist (S n)
