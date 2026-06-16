package flate

import (
	"bytes"
	standardFlate "compress/flate"
	"crypto/sha256"
	"encoding/binary"
	"errors"
	"io"
	"testing"
)

func TestNewReader_RawDeflateByteParity(t *testing.T) {
	testCases := []struct {
		name  string
		input []byte
		level int
	}{
		{
			name:  "empty/no-compression",
			input: []byte{},
			level: standardFlate.NoCompression,
		},
		{
			name:  "small-text/default",
			input: []byte("hello, parity baseline\n"),
			level: standardFlate.DefaultCompression,
		},
		{
			name:  "repeated-128k/best-compression",
			input: repeatedBytes([]byte("repeatable-deflate-parity-"), 128<<10),
			level: standardFlate.BestCompression,
		},
		{
			name:  "random-64k/best-speed",
			input: deterministicBytes(64 << 10),
			level: standardFlate.BestSpeed,
		},
		{
			name:  "mixed-128k/huffman-only",
			input: mixedDeterministicBytes(128 << 10),
			level: standardFlate.HuffmanOnly,
		},
	}

	for _, testCase := range testCases {
		t.Run(testCase.name, func(t *testing.T) {
			compressed := mustCompressRawDeflate(
				t,
				testCase.input,
				testCase.level,
			)
			standardOutput := mustReadAll(
				t,
				compressed,
				standardFlate.NewReader,
			)
			forkOutput := mustReadAll(t, compressed, NewReader)

			if !bytes.Equal(testCase.input, standardOutput) {
				t.Fatalf(
					"standard flate output mismatch: got %q want %q",
					standardOutput,
					testCase.input,
				)
			}

			if !bytes.Equal(testCase.input, forkOutput) {
				t.Fatalf(
					"fork flate output mismatch: got %q want %q",
					forkOutput,
					testCase.input,
				)
			}

			if !bytes.Equal(standardOutput, forkOutput) {
				t.Fatalf(
					"decoded output mismatch: standard=%q fork=%q",
					standardOutput,
					forkOutput,
				)
			}
		})
	}
}

func TestNewReader_RawDeflateCorruptByteParity(t *testing.T) {
	testCases := []struct {
		name       string
		compressed []byte
	}{
		{
			name:       "invalid-btype",
			compressed: []byte{0x06},
		},
		{
			name:       "truncated-stored",
			compressed: []byte{0x01, 0x05, 0x00, 0xfa, 0xff, 'h', 'e'},
		},
	}

	for _, testCase := range testCases {
		t.Run(testCase.name, func(t *testing.T) {
			standardOutput, standardErr := readAllRawDeflate(
				t,
				testCase.compressed,
				standardFlate.NewReader,
			)
			forkOutput, forkErr := readAllRawDeflate(
				t,
				testCase.compressed,
				NewReader,
			)

			if !bytes.Equal(standardOutput, forkOutput) {
				t.Fatalf(
					"partial output mismatch: standard=%x fork=%x",
					standardOutput,
					forkOutput,
				)
			}

			if got, want := errorClass(standardErr), errorClass(forkErr); got != want {
				t.Fatalf(
					"error class mismatch: standard=%s fork=%s",
					got,
					want,
				)
			}
		})
	}
}

func TestNewReaderDict_RawDeflateByteParity(t *testing.T) {
	testCases := []struct {
		name  string
		dict  []byte
		input []byte
		level int
	}{
		{
			name:  "shared-prefix/default",
			dict:  []byte("shared deflate dictionary prefix\n"),
			input: []byte("shared deflate dictionary prefix\npayload line\npayload line\n"),
			level: standardFlate.DefaultCompression,
		},
		{
			name:  "repeated-dictionary/best-compression",
			dict:  []byte("dictionary-token-000 dictionary-token-001 dictionary-token-002 "),
			input: repeatedBytes([]byte("dictionary-token-001 dictionary-token-002 "), 32<<10),
			level: standardFlate.BestCompression,
		},
	}

	for _, testCase := range testCases {
		t.Run(testCase.name, func(t *testing.T) {
			compressed := mustCompressRawDeflateDict(
				t,
				testCase.input,
				testCase.dict,
				testCase.level,
			)
			standardOutput := mustReadAll(
				t,
				compressed,
				func(r io.Reader) io.ReadCloser {
					return standardFlate.NewReaderDict(r, testCase.dict)
				},
			)
			forkOutput := mustReadAll(
				t,
				compressed,
				func(r io.Reader) io.ReadCloser {
					return NewReaderDict(r, testCase.dict)
				},
			)

			if !bytes.Equal(testCase.input, standardOutput) {
				t.Fatalf(
					"standard flate output mismatch: got %q want %q",
					standardOutput,
					testCase.input,
				)
			}

			if !bytes.Equal(testCase.input, forkOutput) {
				t.Fatalf(
					"fork flate output mismatch: got %q want %q",
					forkOutput,
					testCase.input,
				)
			}

			if !bytes.Equal(standardOutput, forkOutput) {
				t.Fatalf(
					"decoded output mismatch: standard=%q fork=%q",
					standardOutput,
					forkOutput,
				)
			}
		})
	}
}

func deterministicBytes(size int) []byte {
	data := make([]byte, size)
	fillDeterministic(data, 1)
	return data
}

func repeatedBytes(pattern []byte, size int) []byte {
	return bytes.Repeat(pattern, (size+len(pattern)-1)/len(pattern))[:size]
}

func mixedDeterministicBytes(size int) []byte {
	var data bytes.Buffer
	seed := uint64(2)

	for data.Len() < size {
		data.WriteString("mixed-deflate-parity-")
		data.Write(bytes.Repeat([]byte{'A'}, 97))

		chunk := make([]byte, 257)
		fillDeterministic(chunk, seed)
		seed++
		data.Write(chunk)
	}

	return data.Bytes()[:size]
}

func fillDeterministic(dst []byte, seed uint64) {
	var counter uint64
	var block [16]byte

	for offset := 0; offset < len(dst); {
		binary.LittleEndian.PutUint64(block[:8], seed)
		binary.LittleEndian.PutUint64(block[8:], counter)

		sum := sha256.Sum256(block[:])
		offset += copy(dst[offset:], sum[:])
		counter++
	}
}

func errorClass(err error) string {
	if err == nil {
		return "nil"
	}

	switch {
	case errors.Is(err, io.ErrUnexpectedEOF):
		return "unexpected-eof"
	case errors.Is(err, io.EOF):
		return "eof"
	}

	var standardCorrupt standardFlate.CorruptInputError
	if errors.As(err, &standardCorrupt) {
		return "corrupt-input"
	}

	var forkCorrupt CorruptInputError
	if errors.As(err, &forkCorrupt) {
		return "corrupt-input"
	}

	var standardInternal standardFlate.InternalError
	if errors.As(err, &standardInternal) {
		return "internal-error"
	}

	var forkInternal InternalError
	if errors.As(err, &forkInternal) {
		return "internal-error"
	}

	return "other"
}

func readAllRawDeflate(
	t *testing.T,
	compressed []byte,
	newReader func(io.Reader) io.ReadCloser,
) ([]byte, error) {
	t.Helper()

	reader := newReader(bytes.NewReader(compressed))
	decompressed, err := io.ReadAll(reader)
	closeErr := reader.Close()
	if err == nil {
		err = closeErr
	}

	return decompressed, err
}

func mustCompressRawDeflate(t *testing.T, input []byte, level int) []byte {
	t.Helper()

	var compressed bytes.Buffer

	writer, err := standardFlate.NewWriter(&compressed, level)
	if err != nil {
		t.Fatalf("create raw deflate writer: %v", err)
	}

	if _, err = writer.Write(input); err != nil {
		t.Fatalf("write raw deflate stream: %v", err)
	}

	if err = writer.Close(); err != nil {
		t.Fatalf("close raw deflate writer: %v", err)
	}

	return compressed.Bytes()
}

func mustCompressRawDeflateDict(
	t *testing.T,
	input []byte,
	dict []byte,
	level int,
) []byte {
	t.Helper()

	var compressed bytes.Buffer

	writer, err := standardFlate.NewWriterDict(&compressed, level, dict)
	if err != nil {
		t.Fatalf("create raw deflate dict writer: %v", err)
	}

	if _, err = writer.Write(input); err != nil {
		t.Fatalf("write raw deflate dict stream: %v", err)
	}

	if err = writer.Close(); err != nil {
		t.Fatalf("close raw deflate dict writer: %v", err)
	}

	return compressed.Bytes()
}

func mustReadAll(
	t *testing.T,
	compressed []byte,
	newReader func(io.Reader) io.ReadCloser,
) []byte {
	t.Helper()

	reader := newReader(bytes.NewReader(compressed))
	decompressed, err := io.ReadAll(reader)
	closeErr := reader.Close()

	if err != nil {
		t.Fatalf("read raw deflate stream: %v", err)
	}

	if closeErr != nil {
		t.Fatalf("close raw deflate reader: %v", closeErr)
	}

	return decompressed
}
