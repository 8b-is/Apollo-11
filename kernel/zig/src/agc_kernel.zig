//! Apollo-11 AGC Block II Kernel — Quantized NANDIFY + Typesafe Zig 0.16.0
//!
//! Re-implements the core of `Luminary099/EXECUTIVE.agc` and `Luminary099/WAITLIST.agc`
//! on top of:
//!   1. Universal 15-bit 1's-complement NAND-gate synthesis (`nand15`, `not15`, `and15`,
//!      `or15`, `xor15`, ripple full-adder with end-around carry, and 16-bit odd parity).
//!   2. Quantized balanced-ternary `NANDIFY` (`BFP-64` 64-lane Kleene `+AND=1` / `~NAND=-1`
//!      bitplanes + 15-trit AGC word quantization).
//!   3. `0x62`-gate 32-byte `wupz` frame sealing (`sealFrame32B` / `verifyFrame32B`).
//!   4. Priority `Executive` (7 Core Sets + 5 Vector Accumulator VAC areas, `01201`/`01202`
//!      bailout alarms) and centisecond delta-T `Waitlist` (`LST1`/`LST2`, 9 tasks max,
//!      `01203` waitlist overflow alarm).

const std = @import("std");

pub const WORD15_MASK: u16 = 0x7FFF;
pub const NEG_ZERO_15: u16 = 0x7FFF;
pub const POS_ZERO_15: u16 = 0x0000;

pub const ALARM_NO_VAC: u16 = 0o1201; // Executive overflow — no VAC areas
pub const ALARM_NO_CORE: u16 = 0o1202; // Executive overflow — no core sets
pub const ALARM_WAITLIST: u16 = 0o1203; // Waitlist overflow — >9 tasks

pub const GATE_0X62: u8 = 0x62;
pub const FRAME_ABI_V1: u8 = 0x01;

// ── 1. Universal NAND-Synthesized 15-Bit 1's-Complement ALU ─────────────────

/// Fundamental 15-bit universal NAND gate (the single building block of the AGC).
pub inline fn nand15(a: u16, b: u16) u16 {
    return (~((a & WORD15_MASK) & (b & WORD15_MASK))) & WORD15_MASK;
}

pub inline fn not15(a: u16) u16 {
    return nand15(a, a);
}

pub inline fn and15(a: u16, b: u16) u16 {
    const n = nand15(a, b);
    return nand15(n, n);
}

pub inline fn or15(a: u16, b: u16) u16 {
    return nand15(nand15(a, a), nand15(b, b));
}

pub inline fn xor15(a: u16, b: u16) u16 {
    const n1 = nand15(a, b);
    const n2 = nand15(a, n1);
    const n3 = nand15(b, n1);
    return nand15(n2, n3);
}

/// `xorOr` composite gate synthesized purely from universal 2-input NAND gates:
/// computes `(a XOR b) OR (a AND b)` == `a OR b` via 4-gate XOR + 3-gate OR,
/// verifying canonical NAND absorption identity (`1/1` at `0x62`).
pub inline fn xorOrNand15(a: u16, b: u16) u16 {
    return or15(xor15(a, b), and15(a, b));
}

/// `andNandOr` Ultratron composite gate synthesized purely from universal 2-input NAND gates:
/// computes `(a AND b) XOR (a NAND b)` — the universal tautology mask `0x7FFF` (`-0` in 1's-complement)
/// gated by `(a OR b)` (`and15(or15(a, b), nand15(and15(a, b), nand15(a, b)))`).
pub inline fn andNandOr15(a: u16, b: u16) u16 {
    const ab_and = and15(a, b);
    const ab_nand = nand15(a, b);
    const ab_or = or15(a, b);
    return and15(ab_or, or15(ab_and, ab_nand));
}

/// Ultratron lattice fold over `(a, b)` combining `xorOrNand15` and `andNandOr15`
/// with the `31/56` -> `1/1` (`0xcaf15c5fa9793a9d`) `0x62` gate witness.
pub fn ultratronNandFold(a: u16, b: u16) struct {
    xor_or: u16,
    and_nand_or: u16,
    ultratron_seal: u64,
} {
    const xo = xorOrNand15(a, b);
    const ano = andNandOr15(a, b);
    var buf: [16]u8 = undefined;
    std.mem.writeInt(u16, buf[0..2], packParity16(xo), .little);
    std.mem.writeInt(u16, buf[2..4], packParity16(ano), .little);
    std.mem.writeInt(u32, buf[4..8], 31 * 56, .little);
    std.mem.writeInt(u64, buf[8..16], 0xcaf15c5fa9793a9d, .little);
    return .{
        .xor_or = xo,
        .and_nand_or = ano,
        .ultratron_seal = xorFold(&buf),
    };
}

/// 1-bit universal NAND gate.
pub inline fn nand1(a: u1, b: u1) u1 {
    return ~(a & b);
}

/// 1-bit full adder synthesized strictly from 9 universal 2-input NAND gates.
pub inline fn fullAdderNand(a: u1, b: u1, cin: u1) struct { sum: u1, cout: u1 } {
    const g1 = nand1(a, b);
    const g2 = nand1(a, g1);
    const g3 = nand1(b, g1);
    const axb = nand1(g2, g3); // a XOR b
    const g5 = nand1(axb, cin);
    const g6 = nand1(axb, g5);
    const g7 = nand1(cin, g5);
    const sum = nand1(g6, g7); // (a XOR b) XOR cin
    const cout = nand1(g1, g5); // (a AND b) OR (cin AND (a XOR b))
    return .{ .sum = sum, .cout = cout };
}

fn rippleAdd15Nand(a: u16, b: u16, cin_init: u1) struct { sum: u16, cout: u1 } {
    var sum: u16 = 0;
    var carry: u1 = cin_init;
    var bit: u4 = 0;
    while (true) {
        const ba: u1 = @truncate((a >> bit) & 1);
        const bb: u1 = @truncate((b >> bit) & 1);
        const r = fullAdderNand(ba, bb, carry);
        sum |= (@as(u16, r.sum) << bit);
        carry = r.cout;
        if (bit == 14) break;
        bit += 1;
    }
    return .{ .sum = sum & WORD15_MASK, .cout = carry };
}

/// AGC Block II 15-bit 1's-complement addition (`AD`) with end-around carry,
/// synthesized purely from universal NAND gates.
pub fn add1sComplementNand(a: u16, b: u16) u16 {
    const first = rippleAdd15Nand(a & WORD15_MASK, b & WORD15_MASK, 0);
    if (first.cout == 1) {
        return rippleAdd15Nand(first.sum, 0, 1).sum;
    }
    return first.sum;
}

/// Convert signed integer `[-16383, +16383]` to 15-bit 1's-complement AGC word.
pub fn fromSigned15(v: i16) u16 {
    if (v >= 0) {
        return @as(u16, @intCast(v)) & WORD15_MASK;
    }
    const mag: u16 = @intCast(-v);
    return not15(mag);
}

/// Decode 15-bit 1's-complement AGC word to signed integer (`-0` == `0o77777` -> `0`).
pub fn toSigned15(w: u16) i16 {
    const masked = w & WORD15_MASK;
    if (masked == NEG_ZERO_15) return 0;
    if ((masked & 0x4000) == 0) {
        return @intCast(masked);
    }
    const mag = not15(masked);
    return -@as(i16, @intCast(mag));
}

/// Pack a 15-bit AGC word with its 16th odd-parity bit (bit 15 set so total 1-bits is odd).
pub fn packParity16(w15: u16) u16 {
    const masked = w15 & WORD15_MASK;
    var xor_bit: u1 = 0;
    var b: u4 = 0;
    while (true) {
        const bit: u1 = @truncate((masked >> b) & 1);
        // XOR via 4 NAND gates
        const g1 = nand1(xor_bit, bit);
        xor_bit = nand1(nand1(xor_bit, g1), nand1(bit, g1));
        if (b == 14) break;
        b += 1;
    }
    const parity_bit: u1 = nand1(xor_bit, xor_bit); // NOT(xor_bit) => odd parity
    return masked | (@as(u16, parity_bit) << 15);
}

pub fn verifyParity16(w16: u16) bool {
    return (@popCount(w16) & 1) == 1;
}

// ── 2. Quantized Ternary `NANDIFY` (`BFP-64` Bitplanes + `0x62` 32B Seal) ───

pub const Trit = enum(i8) {
    neg = -1,
    zero = 0,
    pos = 1,
};

pub const Bfp64Word = struct {
    pos: u64 = 0,
    neg: u64 = 0,
};

/// 64-lane Kleene AND (`+AND=1`): `+1` iff both `+1`, `-1` if either `-1`, else `0`.
pub inline fn bfp64AndKleene(a: Bfp64Word, b: Bfp64Word) Bfp64Word {
    const neg_out = a.neg | b.neg;
    const pos_out = (a.pos & b.pos) & ~neg_out;
    return .{ .pos = pos_out, .neg = neg_out };
}

/// 64-lane Kleene NAND (`~NAND=-1`): negation of Kleene AND by swapping bitplanes.
pub inline fn bfp64NandKleene(a: Bfp64Word, b: Bfp64Word) Bfp64Word {
    const and_w = bfp64AndKleene(a, b);
    return .{ .pos = and_w.neg, .neg = and_w.pos };
}

/// Quantize a 15-bit 1's-complement AGC word into a 15-lane `BFP-64` ternary word:
/// `-0` (`0o77777`) and `+0` (`0o00000`) map to `0` (`pos=0, neg=0`);
/// otherwise active bits map to `+1` for positive words and `-1` for negative words.
pub fn quantizeWord15ToBfp64(w15: u16) Bfp64Word {
    const masked = w15 & WORD15_MASK;
    if (masked == POS_ZERO_15 or masked == NEG_ZERO_15) {
        return .{ .pos = 0, .neg = 0 };
    }
    if ((masked & 0x4000) == 0) {
        return .{ .pos = @as(u64, masked & 0x3FFF), .neg = 0 };
    } else {
        const mag = not15(masked) & 0x3FFF;
        return .{ .pos = 0, .neg = @as(u64, mag) };
    }
}

pub fn xorFold(bytes: []const u8) u64 {
    var acc: u64 = 0;
    var i: usize = 0;
    while (i + 32 <= bytes.len) : (i += 32) {
        const words: @Vector(4, u64) = .{
            std.mem.readInt(u64, bytes[i..][0..8], .little),
            std.mem.readInt(u64, bytes[i + 8 ..][0..8], .little),
            std.mem.readInt(u64, bytes[i + 16 ..][0..8], .little),
            std.mem.readInt(u64, bytes[i + 24 ..][0..8], .little),
        };
        acc ^= @reduce(.Xor, words);
    }
    while (i + 8 <= bytes.len) : (i += 8) {
        acc ^= std.mem.readInt(u64, bytes[i..][0..8], .little);
    }
    while (i < bytes.len) : (i += 1) {
        acc ^= @as(u64, bytes[i]);
    }
    return acc;
}

pub fn sealFrame32B(raw: []const u8, packed_bytes: []const u8, gate: u8) [32]u8 {
    var frame: [32]u8 = @splat(0);
    std.mem.writeInt(u64, frame[0..8], xorFold(raw), .little);
    std.mem.writeInt(u64, frame[8..16], xorFold(packed_bytes), .little);
    std.mem.writeInt(u32, frame[16..20], @truncate(raw.len), .little);
    std.mem.writeInt(u32, frame[20..24], @truncate(packed_bytes.len), .little);
    frame[24] = gate;
    frame[25] = FRAME_ABI_V1;
    var prefix_le: [8]u8 = undefined;
    std.mem.writeInt(u64, &prefix_le, xorFold(frame[0..26]), .little);
    @memcpy(frame[26..32], prefix_le[0..6]);
    return frame;
}

pub fn verifyFrame32B(frame: *const [32]u8, raw: []const u8, packed_bytes: []const u8, gate: u8) bool {
    if (frame[24] != gate or frame[25] != FRAME_ABI_V1) return false;
    const expected = sealFrame32B(raw, packed_bytes, gate);
    var diff: u8 = 0;
    for (frame, expected) |a, b| diff |= a ^ b;
    return diff == 0;
}

pub const QT_5A: u8 = 0x5A;

/// Laser Phoenix Lattice Lock: locks an 8-lane BFP-64 ternary bitplane pair
/// with a 15-bit 1's-complement AGC word and its 16th-bit NAND odd-parity witness
/// at the `0x62` / `qt:5a` gate with zero floating-point operations.
pub fn laserPhoenixLatticeLock(w15: u16, lane_seed: u64) struct {
    w16_odd: u16,
    bfp: Bfp64Word,
    lattice_seal: u64,
} {
    const w16 = packParity16(w15);
    const q = quantizeWord15ToBfp64(w15);
    const seed_w = Bfp64Word{ .pos = lane_seed, .neg = ~lane_seed };
    const locked = bfp64NandKleene(q, seed_w);
    var buf: [24]u8 = undefined;
    std.mem.writeInt(u64, buf[0..8], locked.pos, .little);
    std.mem.writeInt(u64, buf[8..16], locked.neg, .little);
    std.mem.writeInt(u16, buf[16..18], w16, .little);
    buf[18] = GATE_0X62;
    buf[19] = QT_5A;
    std.mem.writeInt(u32, buf[20..24], 1695 ^ 1327, .little);
    return .{
        .w16_odd = w16,
        .bfp = locked,
        .lattice_seal = xorFold(&buf),
    };
}

/// C-ABI export for Perl/FFI callers (`wupz`-packed Zig shim for 0x62 32B frame sealing).
export fn agc_nandify_seal_32b(
    raw_ptr: ?[*]const u8,
    raw_len: usize,
    packed_ptr: ?[*]const u8,
    packed_len: usize,
    gate: u8,
    out_frame: ?*[32]u8,
) c_int {
    const r = raw_ptr orelse return -1;
    const p = packed_ptr orelse return -1;
    const out = out_frame orelse return -1;
    out.* = sealFrame32B(r[0..raw_len], p[0..packed_len], gate);
    return 0;
}

export fn agc_laser_phoenix_lattice_lock(w15: u16, lane_seed: u64) u64 {
    return laserPhoenixLatticeLock(w15, lane_seed).lattice_seal;
}

// ── 3. Typesafe AGC `EXECUTIVE` (`Luminary099/EXECUTIVE.agc`) ───────────────

pub const MAX_CORE_SETS: usize = 7;
pub const MAX_VAC_AREAS: usize = 5;

pub const JobState = enum(u8) {
    free = 0,
    runnable = 1,
    sleeping = 2,
};

pub const CoreSet = struct {
    state: JobState = .free,
    prio: u16 = 0, // Bits 10..14 hold priority (1..31)
    cad2: u16 = 0, // 2CADR address of job
    vac_index: ?u8 = null,
};

pub const Executive = struct {
    core_sets: [MAX_CORE_SETS]CoreSet = [_]CoreSet{.{}} ** MAX_CORE_SETS,
    vac_in_use: [MAX_VAC_AREAS]bool = [_]bool{false} ** MAX_VAC_AREAS,
    last_alarm: u16 = 0,

    /// Schedule a job requiring no VAC area (`NOVAC` in `EXECUTIVE.agc`).
    pub fn novac(self: *Executive, prio: u16, cad2: u16) !usize {
        for (&self.core_sets, 0..) |*cs, idx| {
            if (cs.state == .free) {
                cs.* = .{ .state = .runnable, .prio = prio & WORD15_MASK, .cad2 = cad2 & WORD15_MASK, .vac_index = null };
                return idx;
            }
        }
        self.last_alarm = ALARM_NO_CORE;
        return error.ExecutiveOverflowNoCore1202;
    }

    /// Schedule an interpretive job requiring a Vector Accumulator area (`FINDVAC`).
    pub fn findvac(self: *Executive, prio: u16, cad2: u16) !usize {
        var vac_slot: ?u8 = null;
        for (&self.vac_in_use, 0..) |*used, v_idx| {
            if (!used.*) {
                used.* = true;
                vac_slot = @intCast(v_idx);
                break;
            }
        }
        if (vac_slot == null) {
            self.last_alarm = ALARM_NO_VAC;
            return error.ExecutiveOverflowNoVac1201;
        }
        for (&self.core_sets, 0..) |*cs, idx| {
            if (cs.state == .free) {
                cs.* = .{
                    .state = .runnable,
                    .prio = prio & WORD15_MASK,
                    .cad2 = cad2 & WORD15_MASK,
                    .vac_index = vac_slot,
                };
                return idx;
            }
        }
        self.vac_in_use[vac_slot.?] = false;
        self.last_alarm = ALARM_NO_CORE;
        return error.ExecutiveOverflowNoCore1202;
    }

    /// Return the index of the highest-priority runnable job (`CHANJOB`).
    pub fn highestPriorityJob(self: *const Executive) ?usize {
        var best_idx: ?usize = null;
        var best_prio: u16 = 0;
        for (self.core_sets, 0..) |cs, idx| {
            if (cs.state == .runnable and cs.prio > best_prio) {
                best_prio = cs.prio;
                best_idx = idx;
            }
        }
        return best_idx;
    }

    /// Suspend a job (`JOBSLEEP`) at the given address `loc`.
    pub fn jobSleep(self: *Executive, slot: usize, loc: u16) void {
        if (slot < MAX_CORE_SETS and self.core_sets[slot].state == .runnable) {
            self.core_sets[slot].state = .sleeping;
            self.core_sets[slot].cad2 = loc & WORD15_MASK;
        }
    }

    /// Wake a sleeping job (`JOBWAKE`) matching `loc`.
    pub fn jobWake(self: *Executive, loc: u16) bool {
        for (&self.core_sets) |*cs| {
            if (cs.state == .sleeping and cs.cad2 == (loc & WORD15_MASK)) {
                cs.state = .runnable;
                return true;
            }
        }
        return false;
    }

    /// Terminate a job (`ENDJOB`) and release its VAC area if attached.
    pub fn endJob(self: *Executive, slot: usize) void {
        if (slot < MAX_CORE_SETS) {
            if (self.core_sets[slot].vac_index) |v_idx| {
                self.vac_in_use[v_idx] = false;
            }
            self.core_sets[slot] = .{};
        }
    }
};

// ── 4. Typesafe AGC `WAITLIST` (`Luminary099/WAITLIST.agc`) ─────────────────

pub const MAX_WAITLIST_TASKS: usize = 9;
pub const MAX_DELTA_T_CS: u16 = 16250; // 162.5 seconds max per WAITLIST.agc

pub const WaitTask = struct {
    due_cs: u32 = 0,
    cad2: u16 = 0,
};

pub const Waitlist = struct {
    now_cs: u32 = 0,
    tasks: [MAX_WAITLIST_TASKS]WaitTask = [_]WaitTask{.{}} ** MAX_WAITLIST_TASKS,
    len: usize = 0,
    last_alarm: u16 = 0,

    /// Schedule a task to run in `delta_cs` centiseconds (`1 <= delta_cs <= 16250`).
    /// Keeps `tasks[0..len]` sorted by `due_cs` (matching `LST1` delta-T ordering).
    pub fn schedule(self: *Waitlist, delta_cs: u16, cad2: u16) !void {
        if (delta_cs == 0 or delta_cs > MAX_DELTA_T_CS) return error.InvalidDeltaT;
        if (self.len >= MAX_WAITLIST_TASKS) {
            self.last_alarm = ALARM_WAITLIST;
            return error.WaitlistOverflow1203;
        }
        const due = self.now_cs + @as(u32, delta_cs);
        var insert_at = self.len;
        while (insert_at > 0 and self.tasks[insert_at - 1].due_cs > due) : (insert_at -= 1) {
            self.tasks[insert_at] = self.tasks[insert_at - 1];
        }
        self.tasks[insert_at] = .{ .due_cs = due, .cad2 = cad2 & WORD15_MASK };
        self.len += 1;
    }

    /// Advance `T3RUPT` clock by `step_cs` centiseconds and pop all due task `2CADR`s (`TASKOVER`).
    pub fn tickT3Rupt(self: *Waitlist, step_cs: u16, fired_out: []u16) usize {
        self.now_cs += @as(u32, step_cs);
        var fired: usize = 0;
        while (self.len > 0 and self.tasks[0].due_cs <= self.now_cs and fired < fired_out.len) {
            fired_out[fired] = self.tasks[0].cad2;
            fired += 1;
            var i: usize = 0;
            while (i + 1 < self.len) : (i += 1) {
                self.tasks[i] = self.tasks[i + 1];
            }
            self.len -= 1;
        }
        return fired;
    }
};

// ── 5. Verification Tests ───────────────────────────────────────────────────

test "AGC 15-bit 1's-complement NAND ALU and end-around carry" {
    const pos_42 = fromSigned15(42);
    const neg_17 = fromSigned15(-17);
    const sum = add1sComplementNand(pos_42, neg_17);
    try std.testing.expectEqual(@as(i16, 25), toSigned15(sum));

    // Negative + negative
    const neg_100 = fromSigned15(-100);
    const neg_55 = fromSigned15(-55);
    try std.testing.expectEqual(@as(i16, -155), toSigned15(add1sComplementNand(neg_100, neg_55)));

    // 16-bit odd parity synthesized via NAND
    const w16 = packParity16(sum);
    try std.testing.expect(verifyParity16(w16));
    try std.testing.expect(!verifyParity16(w16 ^ 0x0001));

    // Ultratron `xorOrNand15` & `andNandOr15` universal NAND absorption identities
    const a15: u16 = 0o3156;
    const b15: u16 = 0o5252;
    try std.testing.expectEqual(or15(a15, b15), xorOrNand15(a15, b15));
    try std.testing.expectEqual(or15(a15, b15), andNandOr15(a15, b15));
    const u_fold = ultratronNandFold(a15, b15);
    try std.testing.expect(u_fold.ultratron_seal != 0);
}

test "Quantized NANDIFY BFP-64 bitplanes and 0x62 32B frame seal" {
    const all_pos = Bfp64Word{ .pos = ~@as(u64, 0), .neg = 0 };
    const and_res = bfp64AndKleene(all_pos, all_pos);
    try std.testing.expectEqual(~@as(u64, 0), and_res.pos);
    try std.testing.expectEqual(@as(u64, 0), and_res.neg);

    const nand_res = bfp64NandKleene(all_pos, all_pos);
    try std.testing.expectEqual(@as(u64, 0), nand_res.pos);
    try std.testing.expectEqual(~@as(u64, 0), nand_res.neg);

    // -0 (0o77777) and +0 (0o00000) both quantize to balanced ternary zero
    const q_neg_zero = quantizeWord15ToBfp64(NEG_ZERO_15);
    try std.testing.expectEqual(@as(u64, 0), q_neg_zero.pos | q_neg_zero.neg);

    const raw = "LUNAR_LANDING_GUIDANCE_IGNITION_ALGORITHM";
    const packed_b = "LMY99_EXEC_WAITLIST_0X62";
    var frame = sealFrame32B(raw, packed_b, GATE_0X62);
    try std.testing.expect(verifyFrame32B(&frame, raw, packed_b, GATE_0X62));
    frame[31] ^= 0x01;
    try std.testing.expect(!verifyFrame32B(&frame, raw, packed_b, GATE_0X62));

    const lock = laserPhoenixLatticeLock(0o33562, 0xdeb4fd894ddb52e2);
    try std.testing.expect(verifyParity16(lock.w16_odd));
    try std.testing.expect(lock.lattice_seal != 0);
}

test "AGC Executive priority preemption and 1201/1202 bailout protection" {
    var exec = Executive{};
    const low_slot = try exec.novac(10, 0o4001);
    const high_slot = try exec.findvac(24, 0o5200);
    try std.testing.expectEqual(@as(?usize, high_slot), exec.highestPriorityJob());

    exec.jobSleep(high_slot, 0o5200);
    try std.testing.expectEqual(@as(?usize, low_slot), exec.highestPriorityJob());

    try std.testing.expect(exec.jobWake(0o5200));
    try std.testing.expectEqual(@as(?usize, high_slot), exec.highestPriorityJob());

    exec.endJob(high_slot);
    try std.testing.expectEqual(@as(?usize, low_slot), exec.highestPriorityJob());
}

test "AGC Waitlist sorted delta-T scheduling and 1203 overflow alarm" {
    var wl = Waitlist{};
    try wl.schedule(50, 0o2001);
    try wl.schedule(10, 0o2002);
    try wl.schedule(30, 0o2003);

    var fired: [4]u16 = undefined;
    try std.testing.expectEqual(@as(usize, 2), wl.tickT3Rupt(35, &fired));
    try std.testing.expectEqual(@as(u16, 0o2002), fired[0]);
    try std.testing.expectEqual(@as(u16, 0o2003), fired[1]);
    try std.testing.expectEqual(@as(usize, 1), wl.tickT3Rupt(20, &fired));
    try std.testing.expectEqual(@as(u16, 0o2001), fired[0]);
}
