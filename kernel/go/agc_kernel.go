package agckernel

import (
	"encoding/binary"
	"errors"
	"math/bits"
)

const (
	Word15Mask uint16 = 0x7FFF
	NegZero15  uint16 = 0x7FFF
	PosZero15  uint16 = 0x0000

	AlarmNoVac    uint16 = 0o1201
	AlarmNoCore   uint16 = 0o1202
	AlarmWaitlist uint16 = 0o1203

	Gate0x62   uint8 = 0x62
	FrameABIV1 uint8 = 0x01

	MaxCoreSets      = 7
	MaxVacAreas      = 5
	MaxWaitlistTasks = 9
	MaxDeltaTCs      = 16250
)

func Nand15(a, b uint16) uint16 {
	return (^((a & Word15Mask) & (b & Word15Mask))) & Word15Mask
}

func Not15(a uint16) uint16 {
	return Nand15(a, a)
}

func nand1(a, b uint8) uint8 {
	return (^(a & b)) & 1
}

func fullAdderNand(a, b, cin uint8) (sum, cout uint8) {
	g1 := nand1(a, b)
	g2 := nand1(a, g1)
	g3 := nand1(b, g1)
	axb := nand1(g2, g3)
	g5 := nand1(axb, cin)
	g6 := nand1(axb, g5)
	g7 := nand1(cin, g5)
	sum = nand1(g6, g7)
	cout = nand1(g1, g5)
	return sum, cout
}

func rippleAdd15Nand(a, b uint16, cinInit uint8) (uint16, uint8) {
	var sum uint16
	carry := cinInit & 1
	for bit := uint(0); bit < 15; bit++ {
		ba := uint8((a >> bit) & 1)
		bb := uint8((b >> bit) & 1)
		s, c := fullAdderNand(ba, bb, carry)
		sum |= uint16(s) << bit
		carry = c
	}
	return sum & Word15Mask, carry
}

// Add1sComplementNand computes 15-bit 1's-complement addition with end-around
// carry synthesized purely from universal 2-input NAND gates.
func Add1sComplementNand(a, b uint16) uint16 {
	sum, cout := rippleAdd15Nand(a&Word15Mask, b&Word15Mask, 0)
	if cout == 1 {
		sum2, _ := rippleAdd15Nand(sum, 0, 1)
		return sum2
	}
	return sum
}

func FromSigned15(v int16) uint16 {
	if v >= 0 {
		return uint16(v) & Word15Mask
	}
	return Not15(uint16(-v))
}

func ToSigned15(w uint16) int16 {
	masked := w & Word15Mask
	if masked == NegZero15 {
		return 0
	}
	if (masked & 0x4000) == 0 {
		return int16(masked)
	}
	return -int16(Not15(masked))
}

func PackParity16(w15 uint16) uint16 {
	masked := w15 & Word15Mask
	var xorBit uint8
	for b := uint(0); b < 15; b++ {
		bit := uint8((masked >> b) & 1)
		g1 := nand1(xorBit, bit)
		xorBit = nand1(nand1(xorBit, g1), nand1(bit, g1))
	}
	parity := nand1(xorBit, xorBit)
	return masked | (uint16(parity) << 15)
}

func VerifyParity16(w16 uint16) bool {
	return (bits.OnesCount16(w16) & 1) == 1
}

func BFP64AndKleene(posA, negA, posB, negB uint64) (posOut, negOut uint64) {
	negOut = negA | negB
	posOut = (posA & posB) &^ negOut
	return posOut, negOut
}

func BFP64NandKleene(posA, negA, posB, negB uint64) (posOut, negOut uint64) {
	p, n := BFP64AndKleene(posA, negA, posB, negB)
	return n, p
}

func XORFold(data []byte) uint64 {
	var acc uint64
	i := 0
	for ; i+8 <= len(data); i += 8 {
		acc ^= binary.LittleEndian.Uint64(data[i : i+8])
	}
	for ; i < len(data); i++ {
		acc ^= uint64(data[i])
	}
	return acc
}

func SealFrame32B(raw, packed []byte, gate uint8) [32]byte {
	var frame [32]byte
	binary.LittleEndian.PutUint64(frame[0:8], XORFold(raw))
	binary.LittleEndian.PutUint64(frame[8:16], XORFold(packed))
	binary.LittleEndian.PutUint32(frame[16:20], uint32(len(raw)))
	binary.LittleEndian.PutUint32(frame[20:24], uint32(len(packed)))
	frame[24] = gate
	frame[25] = FrameABIV1
	var tail [8]byte
	binary.LittleEndian.PutUint64(tail[:], XORFold(frame[0:26]))
	copy(frame[26:32], tail[0:6])
	return frame
}

func VerifyFrame32B(frame [32]byte, raw, packed []byte, gate uint8) bool {
	if frame[24] != gate || frame[25] != FrameABIV1 {
		return false
	}
	expected := SealFrame32B(raw, packed, gate)
	var diff uint8
	for i := 0; i < 32; i++ {
		diff |= frame[i] ^ expected[i]
	}
	return diff == 0
}

type WaitTask struct {
	DueCs uint32
	Cad2  uint16
}

type Waitlist struct {
	NowCs     uint32
	Tasks     [MaxWaitlistTasks]WaitTask
	Len       int
	LastAlarm uint16
}

func (w *Waitlist) Schedule(deltaCs uint16, cad2 uint16) error {
	if deltaCs == 0 || deltaCs > MaxDeltaTCs || w.Len >= MaxWaitlistTasks {
		w.LastAlarm = AlarmWaitlist
		return errors.New("waitlist overflow 01203")
	}
	due := w.NowCs + uint32(deltaCs)
	ins := w.Len
	for ins > 0 && w.Tasks[ins-1].DueCs > due {
		w.Tasks[ins] = w.Tasks[ins-1]
		ins--
	}
	w.Tasks[ins] = WaitTask{DueCs: due, Cad2: cad2 & Word15Mask}
	w.Len++
	return nil
}

func (w *Waitlist) TickT3Rupt(stepCs uint16) []uint16 {
	w.NowCs += uint32(stepCs)
	var fired []uint16
	for w.Len > 0 && w.Tasks[0].DueCs <= w.NowCs {
		fired = append(fired, w.Tasks[0].Cad2)
		for i := 0; i < w.Len-1; i++ {
			w.Tasks[i] = w.Tasks[i+1]
		}
		w.Len--
	}
	return fired
}
