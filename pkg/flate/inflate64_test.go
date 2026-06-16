package flate

import (
	"bytes"
	"io"
	"testing"
)

func TestNewReader64_StoredBlockLiteral(t *testing.T) {
	want := []byte("hello deflate64\n")
	stream := storedBlock(want)

	reader := NewReader64(bytes.NewReader(stream))
	got := mustReadAllAndClose(t, reader)

	if !bytes.Equal(got, want) {
		t.Fatalf("decoded output mismatch: got %q want %q", got, want)
	}
}

func TestNewReader64_ResetPreservesMode(t *testing.T) {
	first := []byte("first deflate64\n")
	second := []byte("second deflate64\n")
	reader := NewReader64(bytes.NewReader(storedBlock(first)))

	if got := reader.(*decompressor).mode; got != decoderModeDeflate64 {
		t.Fatalf("initial mode mismatch: got %d want %d", got, decoderModeDeflate64)
	}
	if got := mustReadAllAndClose(t, reader); !bytes.Equal(got, first) {
		t.Fatalf("initial output mismatch: got %q want %q", got, first)
	}

	if err := reader.(Resetter).Reset(bytes.NewReader(storedBlock(second)), nil); err != nil {
		t.Fatalf("reset Deflate64 reader: %v", err)
	}
	if got := reader.(*decompressor).mode; got != decoderModeDeflate64 {
		t.Fatalf("reset mode mismatch: got %d want %d", got, decoderModeDeflate64)
	}
	if got := mustReadAllAndClose(t, reader); !bytes.Equal(got, second) {
		t.Fatalf("reset output mismatch: got %q want %q", got, second)
	}
}

func TestNewReader64_Distance32768(t *testing.T) {
	seed := deterministicBytes(32768)

	testNewReader64Distance(t, seed, 32768)
}

func TestNewReader64_Distance32769(t *testing.T) {
	seed := deterministicBytes(32769)

	testNewReader64Distance(t, seed, 32769)
}

func TestNewReader64_Distance65536(t *testing.T) {
	seed := deterministicBytes(65536)

	testNewReader64Distance(t, seed, 65536)
}

func TestNewReader64_Length258(t *testing.T) {
	testNewReader64Length(t, 258)
}

func TestNewReader64_Length259(t *testing.T) {
	testNewReader64Length(t, 259)
}

func TestNewReader64_Length65538(t *testing.T) {
	testNewReader64Length(t, 65538)
}

func TestNewReader_Length258Code285(t *testing.T) {
	seed := []byte("x")
	stream := fixedDeflateBlockCode285(t, seed, 1)
	want := append([]byte{}, seed...)
	want = append(want, bytes.Repeat(seed, 258)...)

	reader := NewReader(bytes.NewReader(stream))
	got := mustReadAllAndClose(t, reader)

	if !bytes.Equal(got, want) {
		t.Fatalf("decoded output mismatch: got %q want %q", got, want)
	}
}

func TestNewReader_DistanceSymbolLimit(t *testing.T) {
	testCases := []struct {
		name     string
		seed     []byte
		distance uint64
	}{
		{
			name:     "code-30",
			seed:     deterministicBytes(32769),
			distance: 32769,
		},
		{
			name:     "code-31",
			seed:     deterministicBytes(65536),
			distance: 65536,
		},
	}

	for _, testCase := range testCases {
		t.Run(testCase.name, func(t *testing.T) {
			stream := fixedDeflate64Block(
				t,
				testCase.seed,
				deflate64TestMatch{length: 3, distance: testCase.distance},
			)
			_, err := readAllRawDeflate(t, stream, NewReader)

			if got, want := errorClass(err), "corrupt-input"; got != want {
				t.Fatalf("error class mismatch: got %s want %s", got, want)
			}
		})
	}
}

func TestNewReader_DistanceAlphabetLimit(t *testing.T) {
	testCases := []struct {
		name                string
		distanceSymbolCount int
		wantErrorClass      string
	}{
		{
			name:                "normal-limit",
			distanceSymbolCount: 30,
			wantErrorClass:      "nil",
		},
		{
			name:                "above-normal-limit",
			distanceSymbolCount: 31,
			wantErrorClass:      "corrupt-input",
		},
		{
			name:                "deflate64-limit-in-normal-mode",
			distanceSymbolCount: 32,
			wantErrorClass:      "corrupt-input",
		},
	}

	for _, testCase := range testCases {
		t.Run(testCase.name, func(t *testing.T) {
			got, err := readAllRawDeflate(
				t,
				dynamicDistanceAlphabetBlock(t, testCase.distanceSymbolCount),
				NewReader,
			)

			if len(got) != 0 {
				t.Fatalf("decoded output mismatch: got %q want empty", got)
			}
			if got, want := errorClass(err), testCase.wantErrorClass; got != want {
				t.Fatalf("error class mismatch: got %s want %s", got, want)
			}
		})
	}
}

func TestNewReader64_DistanceAlphabetLimit(t *testing.T) {
	got, err := readAllRawDeflate(
		t,
		dynamicDistanceAlphabetBlock(t, 32),
		NewReader64,
	)

	if len(got) != 0 {
		t.Fatalf("decoded output mismatch: got %q want empty", got)
	}
	if got, want := errorClass(err), "nil"; got != want {
		t.Fatalf("error class mismatch: got %s want %s", got, want)
	}
}

func TestNewReader64_HistoryDistanceBeyondAvailable(t *testing.T) {
	stream := fixedDeflate64Block(
		t,
		[]byte("abc"),
		deflate64TestMatch{length: 3, distance: 4},
	)
	_, err := readAllRawDeflate(t, stream, NewReader64)

	if got, want := errorClass(err), "corrupt-input"; got != want {
		t.Fatalf("error class mismatch: got %s want %s", got, want)
	}
}

func TestNewReader64_TruncatedExtraBits(t *testing.T) {
	_, err := readAllRawDeflate(
		t,
		truncatedDeflate64LengthExtraBitsBlock(),
		NewReader64,
	)

	if got, want := errorClass(err), "unexpected-eof"; got != want {
		t.Fatalf("error class mismatch: got %s want %s", got, want)
	}
}

func TestNewReader64_FixedDeflate64BlockHelper(t *testing.T) {
	stream := fixedDeflate64Block(
		t,
		[]byte("abc"),
		deflate64TestMatch{length: 3, distance: 3},
	)
	want := []byte("abcabc")

	reader := NewReader64(bytes.NewReader(stream))
	got := mustReadAllAndClose(t, reader)

	if !bytes.Equal(got, want) {
		t.Fatalf("decoded output mismatch: got %q want %q", got, want)
	}
}

func TestNewReader64_DynamicDistanceAlphabetBlockHelper(t *testing.T) {
	stream := dynamicDistanceAlphabetBlock(t, 30)

	reader := NewReader64(bytes.NewReader(stream))
	got := mustReadAllAndClose(t, reader)

	if len(got) != 0 {
		t.Fatalf("decoded output mismatch: got %q want empty", got)
	}
}

func testNewReader64Distance(t *testing.T, seed []byte, distance uint64) {
	t.Helper()

	stream := fixedDeflate64Block(
		t,
		seed,
		deflate64TestMatch{length: 3, distance: distance},
	)
	want := append([]byte{}, seed...)
	want = append(want, seed[:3]...)

	reader := NewReader64(bytes.NewReader(stream))
	got := mustReadAllAndClose(t, reader)

	if !bytes.Equal(got, want) {
		t.Fatalf("decoded output mismatch: got %q want %q", got, want)
	}
}

func testNewReader64Length(t *testing.T, length uint64) {
	t.Helper()

	seed := []byte("x")
	stream := fixedDeflate64Block(
		t,
		seed,
		deflate64TestMatch{length: length, distance: 1},
	)
	want := append([]byte{}, seed...)
	want = append(want, bytes.Repeat(seed, int(length))...)

	reader := NewReader64(bytes.NewReader(stream))
	got := mustReadAllAndClose(t, reader)

	if !bytes.Equal(got, want) {
		t.Fatalf("decoded output mismatch: got %q want %q", got, want)
	}
}

type deflate64TestMatch struct {
	length   uint64
	distance uint64
}

type deflate64TestHuffmanCode struct {
	bits uint64
	size uint
}

type deflate64TestBitWriter struct {
	data  []byte
	bits  uint64
	nbits uint
}

func fixedDeflate64Block(
	tb testing.TB,
	literals []byte,
	matches ...deflate64TestMatch,
) []byte {
	tb.Helper()

	literalCodes := fixedDeflate64LiteralCodes()
	var writer deflate64TestBitWriter

	writer.writeBits(1, 1)
	writer.writeBits(1, 2)
	for _, literal := range literals {
		writer.writeCode(literalCodes[int(literal)])
	}
	for _, match := range matches {
		writeDeflate64TestLength(tb, &writer, literalCodes, match.length)
		writeDeflate64TestDistance(tb, &writer, match.distance)
	}
	writer.writeCode(literalCodes[endBlockMarker])

	return writer.bytes()
}

func fixedDeflateBlockCode285(
	tb testing.TB,
	literals []byte,
	distance uint64,
) []byte {
	tb.Helper()

	literalCodes := fixedDeflate64LiteralCodes()
	var writer deflate64TestBitWriter

	writer.writeBits(1, 1)
	writer.writeBits(1, 2)
	for _, literal := range literals {
		writer.writeCode(literalCodes[int(literal)])
	}
	writer.writeCode(literalCodes[285])
	writeDeflate64TestDistance(tb, &writer, distance)
	writer.writeCode(literalCodes[endBlockMarker])

	return writer.bytes()
}

func truncatedDeflate64LengthExtraBitsBlock() []byte {
	literalCodes := fixedDeflate64LiteralCodes()
	var writer deflate64TestBitWriter

	writer.writeBits(1, 1)
	writer.writeBits(1, 2)
	writer.writeCode(literalCodes[285])

	return writer.bytes()
}

func dynamicDistanceAlphabetBlock(
	tb testing.TB,
	distanceSymbolCount int,
) []byte {
	tb.Helper()

	const (
		literalSymbolCount    = 257
		codeLengthSymbolCount = 18
	)

	literalLengths := make([]uint8, literalSymbolCount)
	literalLengths[endBlockMarker] = 1
	distanceLengths, distanceCountBits := deflate64TestDistanceAlphabetLengths(
		tb,
		distanceSymbolCount,
	)

	codeLengthLengths := make([]uint8, numCodes)
	codeLengthLengths[0] = 2
	codeLengthLengths[1] = 2
	codeLengthLengths[4] = 2
	codeLengthLengths[5] = 2
	codeLengthCodes := deflate64TestHuffmanCodes(codeLengthLengths)

	var writer deflate64TestBitWriter
	writer.writeBits(1, 1)
	writer.writeBits(2, 2)
	writer.writeBits(literalSymbolCount-257, 5)
	writer.writeBits(distanceCountBits, 5)
	writer.writeBits(codeLengthSymbolCount-4, 4)
	for i := range codeLengthSymbolCount {
		writer.writeBits(uint64(codeLengthLengths[codeOrder[i]]), 3)
	}
	allLengths := make(
		[]uint8,
		0,
		len(literalLengths)+len(distanceLengths),
	)
	allLengths = append(allLengths, literalLengths...)
	allLengths = append(allLengths, distanceLengths...)
	writeDeflate64TestCodeLengths(
		&writer,
		codeLengthCodes,
		allLengths,
	)

	literalCodes := deflate64TestHuffmanCodes(literalLengths)
	writer.writeCode(literalCodes[endBlockMarker])

	return writer.bytes()
}

func (w *deflate64TestBitWriter) writeCode(code deflate64TestHuffmanCode) {
	w.writeBits(code.bits, code.size)
}

func (w *deflate64TestBitWriter) writeBits(value uint64, count uint) {
	if count == 0 {
		return
	}

	mask := uint64(1)<<count - 1
	w.bits |= (value & mask) << w.nbits
	w.nbits += count
	for w.nbits >= 8 {
		w.data = append(w.data, byte(w.bits&0xff))
		w.bits >>= 8
		w.nbits -= 8
	}
}

func (w *deflate64TestBitWriter) bytes() []byte {
	if w.nbits > 0 {
		w.data = append(w.data, byte(w.bits&0xff))
		w.bits = 0
		w.nbits = 0
	}

	return w.data
}

func fixedDeflate64LiteralCodes() []deflate64TestHuffmanCode {
	lengths := make([]uint8, 288)
	for i := range 144 {
		lengths[i] = 8
	}
	for i := 144; i < 256; i++ {
		lengths[i] = 9
	}
	for i := 256; i < 280; i++ {
		lengths[i] = 7
	}
	for i := 280; i < 288; i++ {
		lengths[i] = 8
	}

	return deflate64TestHuffmanCodes(lengths)
}

func deflate64TestHuffmanCodes(lengths []uint8) []deflate64TestHuffmanCode {
	var count [maxCodeLen]uint16
	for _, length := range lengths {
		if length != 0 {
			count[length]++
		}
	}

	var code uint16
	var nextCode [maxCodeLen]uint16
	for length := 1; length < maxCodeLen; length++ {
		code = (code + count[length-1]) << 1
		nextCode[length] = code
	}

	codes := make([]deflate64TestHuffmanCode, len(lengths))
	for symbol, length := range lengths {
		if length == 0 {
			continue
		}

		codes[symbol] = deflate64TestHuffmanCode{
			bits: uint64(reverseBits(nextCode[length], length)),
			size: uint(length),
		}
		nextCode[length]++
	}

	return codes
}

func deflate64TestDistanceAlphabetLengths(
	tb testing.TB,
	distanceSymbolCount int,
) (lengths []uint8, headerBits uint64) {
	tb.Helper()

	lengths = make([]uint8, distanceSymbolCount)
	switch distanceSymbolCount {
	case 30:
		for i := range lengths {
			lengths[i] = 5
		}
		lengths[0] = 4
		lengths[1] = 4
		return lengths, 29
	case 31:
		for i := range lengths {
			lengths[i] = 5
		}
		lengths[0] = 4
		return lengths, 30
	case 32:
		for i := range lengths {
			lengths[i] = 5
		}
		return lengths, 31
	default:
		tb.Fatalf(
			"unsupported distance alphabet size: %d",
			distanceSymbolCount,
		)
	}

	return nil, 0
}

func writeDeflate64TestCodeLengths(
	writer *deflate64TestBitWriter,
	codeLengthCodes []deflate64TestHuffmanCode,
	lengths []uint8,
) {
	for _, length := range lengths {
		writer.writeCode(codeLengthCodes[length])
	}
}

func writeDeflate64TestLength(
	tb testing.TB,
	writer *deflate64TestBitWriter,
	literalCodes []deflate64TestHuffmanCode,
	length uint64,
) {
	tb.Helper()

	symbol, extra, extraBits := deflate64TestLengthCode(tb, length)
	writer.writeCode(literalCodes[symbol])
	writer.writeBits(extra, extraBits)
}

func deflate64TestLengthCode(
	tb testing.TB,
	length uint64,
) (symbol int, extra uint64, extraBits uint) {
	tb.Helper()

	if length >= 258 && length <= 65538 {
		return 285, length - 3, 16
	}

	bases := [...]uint64{
		3, 4, 5, 6, 7, 8, 9, 10,
		11, 13, 15, 17, 19, 23, 27, 31,
		35, 43, 51, 59, 67, 83, 99, 115,
		131, 163, 195, 227,
	}
	extraBitCounts := [...]uint{
		0, 0, 0, 0, 0, 0, 0, 0,
		1, 1, 1, 1, 2, 2, 2, 2,
		3, 3, 3, 3, 4, 4, 4, 4,
		5, 5, 5, 5,
	}

	for i, base := range bases {
		bits := extraBitCounts[i]
		limit := base + (uint64(1) << bits) - 1
		if length >= base && length <= limit {
			return lengthCodesStart + i, length - base, bits
		}
	}

	tb.Fatalf("unsupported match length: %d", length)
	return 0, 0, 0
}

func writeDeflate64TestDistance(
	tb testing.TB,
	writer *deflate64TestBitWriter,
	distance uint64,
) {
	tb.Helper()

	symbol, extra, extraBits := deflate64TestDistanceCode(tb, distance)
	reversedSymbol := uint64(reverseBits(symbol, 5))
	writer.writeBits(reversedSymbol, 5)
	writer.writeBits(extra, extraBits)
}

func deflate64TestDistanceCode(
	tb testing.TB,
	distance uint64,
) (symbol uint16, extra uint64, extraBits uint) {
	tb.Helper()

	for symbol := range uint16(32) {
		if symbol < 4 {
			if distance == uint64(symbol)+1 {
				return symbol, 0, 0
			}
			continue
		}

		bits := uint(symbol-2) >> 1
		base := uint64(1)<<(bits+1) + 1
		if symbol&1 == 1 {
			base += uint64(1) << bits
		}
		limit := base + (uint64(1) << bits) - 1
		if distance >= base && distance <= limit {
			return symbol, distance - base, bits
		}
	}

	tb.Fatalf("unsupported match distance: %d", distance)
	return 0, 0, 0
}

func storedBlock(data []byte) []byte {
	n := uint16(len(data))
	finalStoredBlockHeader := byte(0x01)
	lengthLowByte := byte(n)
	lengthHighByte := byte(n >> 8)
	lengthComplementLowByte := byte(^n)
	lengthComplementHighByte := byte(^n >> 8)
	storedBlockHeader := []byte{
		finalStoredBlockHeader,
		lengthLowByte, lengthHighByte,
		lengthComplementLowByte, lengthComplementHighByte,
	}
	return append(storedBlockHeader, data...)
}

func mustReadAllAndClose(t *testing.T, reader io.ReadCloser) []byte {
	t.Helper()

	got, err := io.ReadAll(reader)
	closeErr := reader.Close()

	if err != nil {
		t.Fatalf("read Deflate64 stream: %v", err)
	}
	if closeErr != nil {
		t.Fatalf("close Deflate64 reader: %v", closeErr)
	}

	return got
}
