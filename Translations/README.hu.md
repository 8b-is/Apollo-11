# Apollo-11 (Magyar fordítás + `8b-is` Quantized-NAND & Típusbiztos AGC Kernel)

[![NASA][1]][2]
[![SWH]][SWH_URL]
[![Comanche]][ComancheMilestone]
[![Luminary]][LuminaryMilestone]

Az eredeti Apollo–11 fedélzeti irányító számítógép (Apollo Guidance Computer — AGC Block II) forráskódja a parancsnoki egységhez (**Command Module — `Comanche055`**) és a holdkomphoz (**Lunar Module — `Luminary099`**). Digitalizálta a [Virtual AGC][3] csapata és az [MIT Museum][4]. A tároló célja az eredeti Apollo–11 forráskód hiteles megőrzése, kiegészítve a **`8b-is` szuverén típusbiztos poliglott AGC Block II kernel-újraírásával (`kernel/`)** és a **kvantált univerzális `NANDIFY` (`BFP-64` / `SPQT` + `0x62` 32B frame seal)** szintetizátorral.

---

## `8b-is` Quantized-NAND (`NANDIFY`) & Típusbiztos AGC Block II Kernel (`kernel/`)

Az eredeti **AGC Block II** hardver teljes egészében **4 100 darab 3-bemenetű RTL NOR/NAND logikai kapuból** épült fel, **15-bites egyes komplemens (`1's complement`) gépi szavakkal + 1 páratlan paritásbittel (`16 bit`)**, a valós idejű többfeladatos ütemezést pedig Margaret Hamilton és J. Halcombe Laning prioritásos **`EXECUTIVE`** (`Luminary099/EXECUTIVE.agc`) és centiszekundumos delta-időzítő **`WAITLIST`** (`Luminary099/WAITLIST.agc`) kernele végezte (1201/1202 `EXECUTIVE` túlcsordulási riasztásokkal és 1203 `WAITLIST` túlcsordulással).

A [`kernel/`](../kernel/) könyvtár ezt a magot írja újra négy modern, típusbiztos rendszerprogramozási nyelvben (**Zig `0.16.0`**, **Rust**, **Go**, **Idris 2 QTT**):

| Modul | Fájl | Leírás |
|:------|:-----|:-------|
| **Zig `0.16.0` AGC Kernel** | [`kernel/zig/src/agc_kernel.zig`](../kernel/zig/src/agc_kernel.zig) | Univerzális `NAND`-kapukból felépített 15-bites 1-es komplemens ALU (`nand15`, `add1sComplementNand`, vég-átviteles `end-around carry`, 16-bites páratlan paritás), `BFP-64` 64-trites Kleene `+AND=1` / `~NAND=-1` bitplane kvantálás (`SPQT`), `0x62`-gate 32B `wupz` keretpecsételés, valamint típusbiztos `Executive` (`NOVAC`, `FINDVAC`, `CHANG1`, `JOBSLEEP`, `JOBWAKE`, `ENDJOB`, `Alarm 01201`/`01202`) és `Waitlist` (`WAITLIST`, `TASKOVER`, `T3RUPT`, `Alarm 01203`). |
| **Rust AGC Kernel** | [`kernel/rust/src/lib.rs`](../kernel/rust/src/lib.rs) | `#[forbid(unsafe_code)]` típusbiztos Rust implementáció: `Word15` 1-es komplemens `NAND` ALU, `Bfp64Nand` kvantált ternáris kapuk, `Executive` (7 Core Set + 5 VAC terület), `Waitlist` (9 feladatos `LST1`/`LST2` delta-időzítő) és `0x62` 32B frame seal — bitre azonos eredményekkel a Zig kernellel. |
| **Go AGC Kernel** | [`kernel/go/agc_kernel.go`](../kernel/go/agc_kernel.go) | Konkurens, `-race` alatt tesztelt Go referencia- és differenciális ellenőrző (`NandAlu15`, `BFP64NandKleene`, `Executive`, `Waitlist`, `SealFrame32B` a `0x62` kapun). |
| **Idris 2 QTT Specifikáció** | [`kernel/idris/AgcKernel.idr`](../kernel/idris/AgcKernel.idr) | Quantitative Type Theory (`0, 1, ω`) formális specifikáció: lineáris (`1`) VAC terület-tokenek (amelyek fordítási időben kizárják a `1201`/`1202` VAC-szivárgást), univerzális `NAND` teljesség és `Fin 9` korlátos `WAITLIST`. |

### Futtatás és ellenőrzés

```bash
# 1. Zig 0.16.0 AGC Kernel tesztek
zig test kernel/zig/src/agc_kernel.zig

# 2. Rust AGC Kernel tesztek
cargo test --manifest-path kernel/rust/Cargo.toml

# 3. Go AGC Kernel tesztek (-race)
cd kernel/go && go test -v -race ./...
```

---

## Közreműködés

Kérjük, olvasd el a [CONTRIBUTING.md][7] fájlt pull request nyitása előtt.

## Fordítás (Eredeti AGC Assembly)

Ha az eredeti AGC assembly forráskódot (`Comanche055` és `Luminary099`) szeretnéd lefordítani a `yaYUL` assemblerrel, látogass el a [Virtual AGC][8] oldalra.

## Forrásmegjelölés és Státusz

&nbsp;         | &nbsp;
:------------- | :-----
Szerzői jog    | Közkincs (Public domain)
Comanche055    | Az Apollo–11 parancsnoki egységének (Command Module — CM) Colossus 2A fedélzeti szoftvere<br>`Assemble revision 055 of AGC program Comanche by NASA`<br>`2021113-051. 10:28 APR. 1, 1969`
Luminary099    | Az Apollo–11 holdkompjának (Lunar Module — LM) Luminary 1A fedélzeti szoftvere<br>`Assemble revision 001 of AGC program LMY99 by NASA`<br>`2021112-061. 16:27 JUL. 14, 1969`
Assembler      | yaYUL
Kapcsolat      | Ron Burkey <info@sandroid.org>
Weboldal       | www.ibiblio.org/apollo
Digitalizálás  | A forráskódot az MIT Museum eredeti nyomtatott példányainak szkennelt képeiből írták át. A digitalizálást Paul Fjeld végezte, a múzeum részéről Deborah Douglas szervezte. Köszönet mindkettejüknek!

### Szerződés és Jóváhagyások

*A [CONTRACT_AND_APPROVALS.agc] alapján*

Ezt az AGC programot **Colossus 2A** néven is szokás említeni.

A program a parancsnoki egységben (Command Module) való használatra készült az `R-577` jelentés előírásai szerint. A program a `55-23870` DSR projekt keretében készült, a NASA Manned Spacecraft Center támogatásával, a Massachusetts Institute of Technology (MIT) Instrumentation Laboratory-val kötött `NAS 9-4065` szerződés alapján (Cambridge, Massachusetts).

Benyújtotta          | Szerepkör | Dátum
:------------------- | :-------- | :----
Margaret H. Hamilton | Colossus programozási vezető<br>Apollo Guidance and Navigation | 1969. márc. 28.

Jóváhagyta        | Szerepkör | Dátum
:---------------- | :-------- | :----
Daniel J. Lickly  | Igazgató, Mission Program Development<br>Apollo Guidance and Navigation Program | 1969. márc. 28.
Fred H. Martin    | Colossus projektmenedzser<br>Apollo Guidance and Navigation Program | 1969. márc. 28.
Norman E. Sears   | Igazgató, Mission Development<br>Apollo Guidance and Navigation Program | 1969. márc. 28.
Richard H. Battin | Igazgató, Mission Development<br>Apollo Guidance and Navigation Program | 1969. márc. 28.
David G. Hoag     | Igazgató<br>Apollo Guidance and Navigation Program | 1969. márc. 28.
Ralph R. Ragan    | Igazgatóhelyettes<br>Instrumentation Laboratory | 1969. márc. 28.

[CONTRACT_AND_APPROVALS.agc]:../Comanche055/CONTRACT_AND_APPROVALS.agc
[1]:https://flat.badgen.net/badge/NASA/Mission%20Overview/0B3D91
[2]:https://www.nasa.gov/mission_pages/apollo/missions/apollo11.html
[3]:http://www.ibiblio.org/apollo/
[4]:http://web.mit.edu/museum/
[5]:http://www.ibiblio.org/apollo/ScansForConversion/Luminary099/
[6]:http://www.ibiblio.org/apollo/ScansForConversion/Comanche055/
[7]:../CONTRIBUTING.md
[8]:https://github.com/rburkey2005/virtualagc
[SWH]:https://flat.badgen.net/badge/Software%20Heritage/Archive/0B3D91
[SWH_URL]:https://archive.softwareheritage.org/browse/origin/https://github.com/chrislgarry/Apollo-11/
[Comanche]:https://flat.badgen.net/github/milestones/chrislgarry/Apollo-11/1
[ComancheMilestone]:https://github.com/chrislgarry/Apollo-11/milestone/1
[Luminary]:https://flat.badgen.net/github/milestones/chrislgarry/Apollo-11/2
[LuminaryMilestone]:https://github.com/chrislgarry/Apollo-11/milestone/2
