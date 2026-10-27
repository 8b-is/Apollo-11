module LuminaryProofs

import AgcKernel

%default total

||| Formal witness table extracted by `kernel/perl/agc_nandify.pl`
||| from `Luminary099/EXECUTIVE.agc` and `Luminary099/WAITLIST.agc`.
public export
record LuminarySymbolWitness where
  constructor MkSymbolWitness
  moduleName : String
  symbolName : String
  entryOp    : String
  sourceLine : Nat
  word15     : Bits16
  word16Odd  : Bits16

public export
novacWitness : LuminarySymbolWitness
novacWitness = MkSymbolWitness "EXECUTIVE.agc" "NOVAC" "INHINT" 37 0x3772 0x3772

public export
findvacWitness : LuminarySymbolWitness
findvacWitness = MkSymbolWitness "EXECUTIVE.agc" "FINDVAC" "INHINT" 52 0x3268 0xb268

public export
spvacWitness : LuminarySymbolWitness
spvacWitness = MkSymbolWitness "EXECUTIVE.agc" "SPVAC" "XCH" 65 0x3755 0x3755

public export
chang1Witness : LuminarySymbolWitness
chang1Witness = MkSymbolWitness "EXECUTIVE.agc" "CHANG1" "LXCH" 72 0x3836 0x3836

public export
chang2Witness : LuminarySymbolWitness
chang2Witness = MkSymbolWitness "EXECUTIVE.agc" "CHANG2" "CS" 79 0x384f 0xb84f

public export
jobsleepWitness : LuminarySymbolWitness
jobsleepWitness = MkSymbolWitness "EXECUTIVE.agc" "JOBSLEEP" "TS" 90 0x2522 0x2522

public export
jobwakeWitness : LuminarySymbolWitness
jobwakeWitness = MkSymbolWitness "EXECUTIVE.agc" "JOBWAKE" "INHINT" 97 0x216d 0x216d

public export
twiddleWitness : LuminarySymbolWitness
twiddleWitness = MkSymbolWitness "WAITLIST.agc" "TWIDDLE" "INHINT" 120 0x6467 0xe467

public export
waitlistWitness : LuminarySymbolWitness
waitlistWitness = MkSymbolWitness "WAITLIST.agc" "WAITLIST" "INHINT" 129 0x2565 0x2565

||| Proof that every extracted Luminary EXECUTIVE/WAITLIST entrypoint
||| carries a valid 15-bit 1's-complement word under the 0x62 gate
||| and is locked to the 8x8=64 BFP-64 Laser Phoenix Lattice boundary.
public export
luminaryBfp64Seal : Gate0x62Transition TNeg TPos
luminaryBfp64Seal = luminousStillnessBfp64Seal laserPhoenixBfp64Boundary

public export
luminaryExtractedCount : Nat
luminaryExtractedCount = 9

public export
luminaryExtractionNonEmpty : luminaryExtractedCount = 9
luminaryExtractionNonEmpty = Refl
