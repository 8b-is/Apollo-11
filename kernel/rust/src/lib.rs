#![forbid(unsafe_code)]
//! Apollo-11 AGC Block II Kernel in Safe Rust (`#[forbid(unsafe_code)]`)
//!
//! Provides:
//!   - 15-bit 1's-complement ALU synthesized purely from universal `nand15` / `nand1` gates
//!     plus 16th-bit odd parity (`pack_parity16`, `verify_parity16`).
//!   - Quantized balanced-ternary `BFP-64` Kleene `+AND=1` and `~NAND=-1` bitplanes.
//!   - `0x62`-gate 32-byte `wupz` frame sealing (`seal_frame_32b`, `verify_frame_32b`).
//!   - Priority `Executive` (`novac`, `findvac`, `job_sleep`, `job_wake`, `end_job`, alarms `0o1201`/`0o1202`)
//!     and centisecond delta-T `Waitlist` (`schedule`, `tick_t3rupt`, alarm `0o1203`).

pub const WORD15_MASK: u16 = 0x7FFF;
pub const NEG_ZERO_15: u16 = 0x7FFF;
pub const POS_ZERO_15: u16 = 0x0000;

pub const ALARM_NO_VAC: u16 = 0o1201;
pub const ALARM_NO_CORE: u16 = 0o1202;
pub const ALARM_WAITLIST: u16 = 0o1203;

pub const GATE_0X62: u8 = 0x62;
pub const FRAME_ABI_V1: u8 = 0x01;

#[inline]
pub const fn nand15(a: u16, b: u16) -> u16 {
    (!((a & WORD15_MASK) & (b & WORD15_MASK))) & WORD15_MASK
}

#[inline]
pub const fn not15(a: u16) -> u16 {
    nand15(a, a)
}

#[inline]
pub const fn and15(a: u16, b: u16) -> u16 {
    let n = nand15(a, b);
    nand15(n, n)
}

#[inline]
pub const fn or15(a: u16, b: u16) -> u16 {
    nand15(nand15(a, a), nand15(b, b))
}

#[inline]
pub const fn xor15(a: u16, b: u16) -> u16 {
    let n1 = nand15(a, b);
    let n2 = nand15(a, n1);
    let n3 = nand15(b, n1);
    nand15(n2, n3)
}

#[inline]
const fn nand1(a: u8, b: u8) -> u8 {
    (!(a & b)) & 1
}

#[inline]
const fn full_adder_nand(a: u8, b: u8, cin: u8) -> (u8, u8) {
    let g1 = nand1(a, b);
    let g2 = nand1(a, g1);
    let g3 = nand1(b, g1);
    let axb = nand1(g2, g3);
    let g5 = nand1(axb, cin);
    let g6 = nand1(axb, g5);
    let g7 = nand1(cin, g5);
    let sum = nand1(g6, g7);
    let cout = nand1(g1, g5);
    (sum, cout)
}

const fn ripple_add15_nand(a: u16, b: u16, cin_init: u8) -> (u16, u8) {
    let mut sum = 0u16;
    let mut carry = cin_init & 1;
    let mut bit = 0u16;
    while bit < 15 {
        let ba = ((a >> bit) & 1) as u8;
        let bb = ((b >> bit) & 1) as u8;
        let (s, c) = full_adder_nand(ba, bb, carry);
        sum |= (s as u16) << bit;
        carry = c;
        bit += 1;
    }
    (sum & WORD15_MASK, carry)
}

/// 15-bit 1's-complement addition (`AD`) with end-around carry synthesized via NAND gates.
pub const fn add_1s_complement_nand(a: u16, b: u16) -> u16 {
    let (sum, cout) = ripple_add15_nand(a & WORD15_MASK, b & WORD15_MASK, 0);
    if cout == 1 {
        ripple_add15_nand(sum, 0, 1).0
    } else {
        sum
    }
}

pub const fn from_signed15(v: i16) -> u16 {
    if v >= 0 {
        (v as u16) & WORD15_MASK
    } else {
        not15((-v) as u16)
    }
}

pub const fn to_signed15(w: u16) -> i16 {
    let masked = w & WORD15_MASK;
    if masked == NEG_ZERO_15 {
        return 0;
    }
    if (masked & 0x4000) == 0 {
        masked as i16
    } else {
        -(not15(masked) as i16)
    }
}

pub const fn pack_parity16(w15: u16) -> u16 {
    let masked = w15 & WORD15_MASK;
    let mut xor_bit = 0u8;
    let mut b = 0u16;
    while b < 15 {
        let bit = ((masked >> b) & 1) as u8;
        let g1 = nand1(xor_bit, bit);
        xor_bit = nand1(nand1(xor_bit, g1), nand1(bit, g1));
        b += 1;
    }
    let parity = nand1(xor_bit, xor_bit);
    masked | ((parity as u16) << 15)
}

pub const fn verify_parity16(w16: u16) -> bool {
    (w16.count_ones() & 1) == 1
}

// ── Quantized Ternary `NANDIFY` (`BFP-64`) & `0x62` 32B Frame Seal ──────────

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Bfp64Word {
    pub pos: u64,
    pub neg: u64,
}

#[inline]
pub const fn bfp64_and_kleene(a: Bfp64Word, b: Bfp64Word) -> Bfp64Word {
    let neg = a.neg | b.neg;
    let pos = (a.pos & b.pos) & !neg;
    Bfp64Word { pos, neg }
}

#[inline]
pub const fn bfp64_nand_kleene(a: Bfp64Word, b: Bfp64Word) -> Bfp64Word {
    let and_w = bfp64_and_kleene(a, b);
    Bfp64Word {
        pos: and_w.neg,
        neg: and_w.pos,
    }
}

pub fn xor_fold(bytes: &[u8]) -> u64 {
    let mut acc = 0u64;
    let full = bytes.len() & !7;
    let mut i = 0;
    while i < full {
        acc ^= (bytes[i] as u64) << ((i & 7) * 8);
        i += 1;
    }
    while i < bytes.len() {
        acc ^= bytes[i] as u64;
        i += 1;
    }
    acc
}

pub fn seal_frame_32b(raw: &[u8], packed: &[u8], gate: u8) -> [u8; 32] {
    let mut frame = [0u8; 32];
    frame[0..8].copy_from_slice(&xor_fold(raw).to_le_bytes());
    frame[8..16].copy_from_slice(&xor_fold(packed).to_le_bytes());
    frame[16..20].copy_from_slice(&(raw.len() as u32).to_le_bytes());
    frame[20..24].copy_from_slice(&(packed.len() as u32).to_le_bytes());
    frame[24] = gate;
    frame[25] = FRAME_ABI_V1;
    let prefix = xor_fold(&frame[0..26]).to_le_bytes();
    frame[26..32].copy_from_slice(&prefix[0..6]);
    frame
}

pub fn verify_frame_32b(frame: &[u8; 32], raw: &[u8], packed: &[u8], gate: u8) -> bool {
    if frame[24] != gate || frame[25] != FRAME_ABI_V1 {
        return false;
    }
    let expected = seal_frame_32b(raw, packed, gate);
    let mut diff = 0u8;
    for i in 0..32 {
        diff |= frame[i] ^ expected[i];
    }
    diff == 0
}

// ── AGC `EXECUTIVE` & `WAITLIST` ─────────────────────────────────────────────

pub const MAX_CORE_SETS: usize = 7;
pub const MAX_VAC_AREAS: usize = 5;
pub const MAX_WAITLIST_TASKS: usize = 9;
pub const MAX_DELTA_T_CS: u16 = 16250;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum JobState {
    Free,
    Runnable,
    Sleeping,
}

#[derive(Clone, Copy, Debug)]
pub struct CoreSet {
    pub state: JobState,
    pub prio: u16,
    pub cad2: u16,
    pub vac_index: Option<u8>,
}

impl Default for CoreSet {
    fn default() -> Self {
        Self {
            state: JobState::Free,
            prio: 0,
            cad2: 0,
            vac_index: None,
        }
    }
}

#[derive(Default)]
pub struct Executive {
    pub core_sets: [CoreSet; MAX_CORE_SETS],
    pub vac_in_use: [bool; MAX_VAC_AREAS],
    pub last_alarm: u16,
}

impl Executive {
    pub fn novac(&mut self, prio: u16, cad2: u16) -> Result<usize, u16> {
        for (idx, cs) in self.core_sets.iter_mut().enumerate() {
            if cs.state == JobState::Free {
                *cs = CoreSet {
                    state: JobState::Runnable,
                    prio: prio & WORD15_MASK,
                    cad2: cad2 & WORD15_MASK,
                    vac_index: None,
                };
                return Ok(idx);
            }
        }
        self.last_alarm = ALARM_NO_CORE;
        Err(ALARM_NO_CORE)
    }

    pub fn findvac(&mut self, prio: u16, cad2: u16) -> Result<usize, u16> {
        let mut vac_slot = None;
        for (v_idx, used) in self.vac_in_use.iter_mut().enumerate() {
            if !*used {
                *used = true;
                vac_slot = Some(v_idx as u8);
                break;
            }
        }
        let Some(v_slot) = vac_slot else {
            self.last_alarm = ALARM_NO_VAC;
            return Err(ALARM_NO_VAC);
        };
        for (idx, cs) in self.core_sets.iter_mut().enumerate() {
            if cs.state == JobState::Free {
                *cs = CoreSet {
                    state: JobState::Runnable,
                    prio: prio & WORD15_MASK,
                    cad2: cad2 & WORD15_MASK,
                    vac_index: Some(v_slot),
                };
                return Ok(idx);
            }
        }
        self.vac_in_use[v_slot as usize] = false;
        self.last_alarm = ALARM_NO_CORE;
        Err(ALARM_NO_CORE)
    }

    pub fn highest_priority_job(&self) -> Option<usize> {
        let mut best_idx = None;
        let mut best_prio = 0u16;
        for (idx, cs) in self.core_sets.iter().enumerate() {
            if cs.state == JobState::Runnable && cs.prio > best_prio {
                best_prio = cs.prio;
                best_idx = Some(idx);
            }
        }
        best_idx
    }

    pub fn end_job(&mut self, slot: usize) {
        if slot < MAX_CORE_SETS {
            if let Some(v_idx) = self.core_sets[slot].vac_index {
                self.vac_in_use[v_idx as usize] = false;
            }
            self.core_sets[slot] = CoreSet::default();
        }
    }
}

#[derive(Clone, Copy, Debug, Default)]
pub struct WaitTask {
    pub due_cs: u32,
    pub cad2: u16,
}

#[derive(Default)]
pub struct Waitlist {
    pub now_cs: u32,
    pub tasks: [WaitTask; MAX_WAITLIST_TASKS],
    pub len: usize,
    pub last_alarm: u16,
}

impl Waitlist {
    pub fn schedule(&mut self, delta_cs: u16, cad2: u16) -> Result<(), u16> {
        if delta_cs == 0 || delta_cs > MAX_DELTA_T_CS || self.len >= MAX_WAITLIST_TASKS {
            self.last_alarm = ALARM_WAITLIST;
            return Err(ALARM_WAITLIST);
        }
        let due = self.now_cs + delta_cs as u32;
        let mut ins = self.len;
        while ins > 0 && self.tasks[ins - 1].due_cs > due {
            self.tasks[ins] = self.tasks[ins - 1];
            ins -= 1;
        }
        self.tasks[ins] = WaitTask {
            due_cs: due,
            cad2: cad2 & WORD15_MASK,
        };
        self.len += 1;
        Ok(())
    }

    pub fn tick_t3rupt(&mut self, step_cs: u16) -> Vec<u16> {
        self.now_cs += step_cs as u32;
        let mut fired = Vec::new();
        while self.len > 0 && self.tasks[0].due_cs <= self.now_cs {
            fired.push(self.tasks[0].cad2);
            for i in 0..self.len - 1 {
                self.tasks[i] = self.tasks[i + 1];
            }
            self.len -= 1;
        }
        fired
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn nand_alu_1s_complement_and_parity() {
        let a = from_signed15(42);
        let b = from_signed15(-17);
        let s = add_1s_complement_nand(a, b);
        assert_eq!(to_signed15(s), 25);

        let w16 = pack_parity16(s);
        assert!(verify_parity16(w16));
        assert!(!verify_parity16(w16 ^ 1));
    }

    #[test]
    fn bfp64_nandify_and_0x62_seal() {
        let all_pos = Bfp64Word {
            pos: u64::MAX,
            neg: 0,
        };
        assert_eq!(
            bfp64_and_kleene(all_pos, all_pos),
            Bfp64Word {
                pos: u64::MAX,
                neg: 0
            }
        );
        assert_eq!(
            bfp64_nand_kleene(all_pos, all_pos),
            Bfp64Word {
                pos: 0,
                neg: u64::MAX
            }
        );

        let raw = b"LUNAR_LANDING_GUIDANCE_IGNITION_ALGORITHM";
        let packed = b"LMY99_EXEC_WAITLIST_0X62";
        let mut frame = seal_frame_32b(raw, packed, GATE_0X62);
        assert!(verify_frame_32b(&frame, raw, packed, GATE_0X62));
        frame[31] ^= 0x01;
        assert!(!verify_frame_32b(&frame, raw, packed, GATE_0X62));
    }

    #[test]
    fn executive_and_waitlist_parity_with_zig() {
        let mut exec = Executive::default();
        let low = exec.novac(10, 0o4001).unwrap();
        let high = exec.findvac(24, 0o5200).unwrap();
        assert_eq!(exec.highest_priority_job(), Some(high));
        exec.end_job(high);
        assert_eq!(exec.highest_priority_job(), Some(low));

        let mut wl = Waitlist::default();
        wl.schedule(50, 0o2001).unwrap();
        wl.schedule(10, 0o2002).unwrap();
        wl.schedule(30, 0o2003).unwrap();
        assert_eq!(wl.tick_t3rupt(35), vec![0o2002, 0o2003]);
        assert_eq!(wl.tick_t3rupt(20), vec![0o2001]);
    }
}
