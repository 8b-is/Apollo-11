package agckernel

import "testing"

func TestNandAlu15AndParity(t *testing.T) {
	a := FromSigned15(42)
	b := FromSigned15(-17)
	s := Add1sComplementNand(a, b)
	if got := ToSigned15(s); got != 25 {
		t.Fatalf("ToSigned15 = %d, want 25", got)
	}
	w16 := PackParity16(s)
	if !VerifyParity16(w16) {
		t.Fatal("VerifyParity16 rejected valid word")
	}
	if VerifyParity16(w16 ^ 1) {
		t.Fatal("VerifyParity16 accepted flipped bit")
	}
}

func TestBFP64NandAnd0x62Seal(t *testing.T) {
	const allOnes = ^uint64(0)
	pos, neg := BFP64NandKleene(allOnes, 0, allOnes, 0)
	if pos != 0 || neg != allOnes {
		t.Fatalf("BFP64NandKleene = (%#x,%#x), want (0,allOnes)", pos, neg)
	}

	raw := []byte("LUNAR_LANDING_GUIDANCE_IGNITION_ALGORITHM")
	packed := []byte("LMY99_EXEC_WAITLIST_0X62")
	frame := SealFrame32B(raw, packed, Gate0x62)
	if !VerifyFrame32B(frame, raw, packed, Gate0x62) {
		t.Fatal("VerifyFrame32B rejected valid frame")
	}
	frame[31] ^= 0x01
	if VerifyFrame32B(frame, raw, packed, Gate0x62) {
		t.Fatal("VerifyFrame32B accepted tampered frame")
	}
}

func TestWaitlistScheduleAndT3Rupt(t *testing.T) {
	var wl Waitlist
	if err := wl.Schedule(50, 0o2001); err != nil {
		t.Fatal(err)
	}
	if err := wl.Schedule(10, 0o2002); err != nil {
		t.Fatal(err)
	}
	if err := wl.Schedule(30, 0o2003); err != nil {
		t.Fatal(err)
	}
	fired := wl.TickT3Rupt(35)
	if len(fired) != 2 || fired[0] != 0o2002 || fired[1] != 0o2003 {
		t.Fatalf("fired = %v, want [0o2002 0o2003]", fired)
	}
}
