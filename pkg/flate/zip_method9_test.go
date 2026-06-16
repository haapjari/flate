package flate

import (
	"archive/zip"
	"bytes"
	standardFlate "compress/flate"
	"errors"
	"hash/crc32"
	"io"
	"testing"
	"time"
)

const zipMethodDeflate64 = 9

func TestArchiveZIP_Method9RegisteredReader(t *testing.T) {
	entries := archiveZIPTestEntries(t)
	archive := archiveZIPBytes(t, entries)

	reader, err := zip.NewReader(bytes.NewReader(archive), int64(len(archive)))
	if err != nil {
		t.Fatalf("open ZIP archive: %v", err)
	}

	assertArchiveZIPMethod9NeedsRegistration(t, reader)
	reader.RegisterDecompressor(zipMethodDeflate64, NewReader64)

	got := readArchiveZIPEntries(t, reader)
	if len(got) != len(entries) {
		t.Fatalf("entry count mismatch: got %d want %d", len(got), len(entries))
	}

	for _, entry := range entries {
		if !bytes.Equal(got[entry.name], entry.want) {
			t.Fatalf(
				"entry %s output mismatch: got %q want %q",
				entry.name,
				got[entry.name],
				entry.want,
			)
		}
	}
}

type archiveZIPEntry struct {
	name       string
	method     uint16
	want       []byte
	compressed []byte
}

func archiveZIPTestEntries(t *testing.T) []archiveZIPEntry {
	t.Helper()

	stored := []byte("stored ZIP entry\n")
	deflated := []byte("deflated ZIP entry\n")
	deflate64Literal := []byte("9")
	deflate64Match := deflate64TestMatch{length: 259, distance: 1}
	deflate64 := append([]byte{}, deflate64Literal...)
	deflate64 = append(
		deflate64,
		bytes.Repeat(deflate64Literal, int(deflate64Match.length))...,
	)

	return []archiveZIPEntry{
		{
			name:       "stored.txt",
			method:     zip.Store,
			want:       stored,
			compressed: stored,
		},
		{
			name:   "deflate.txt",
			method: zip.Deflate,
			want:   deflated,
			compressed: mustCompressRawDeflate(
				t,
				deflated,
				standardFlate.DefaultCompression,
			),
		},
		{
			name:   "deflate64.txt",
			method: zipMethodDeflate64,
			want:   deflate64,
			compressed: fixedDeflate64Block(
				t,
				deflate64Literal,
				deflate64Match,
			),
		},
	}
}

func archiveZIPBytes(t testing.TB, entries []archiveZIPEntry) []byte {
	t.Helper()

	var archive bytes.Buffer
	writer := zip.NewWriter(&archive)

	for _, entry := range entries {
		header := &zip.FileHeader{
			Name:     entry.name,
			Method:   entry.method,
			Modified: time.Date(2024, 1, 2, 3, 4, 6, 0, time.UTC),
		}
		header.CRC32 = crc32.ChecksumIEEE(entry.want)
		header.CompressedSize64 = uint64(len(entry.compressed))
		header.UncompressedSize64 = uint64(len(entry.want))

		entryWriter, err := writer.CreateRaw(header)
		if err != nil {
			t.Fatalf("create ZIP entry %s: %v", entry.name, err)
		}
		if _, err = entryWriter.Write(entry.compressed); err != nil {
			t.Fatalf("write ZIP entry %s: %v", entry.name, err)
		}
	}

	if err := writer.Close(); err != nil {
		t.Fatalf("close ZIP writer: %v", err)
	}

	return archive.Bytes()
}

func assertArchiveZIPMethod9NeedsRegistration(
	t testing.TB,
	reader *zip.Reader,
) {
	t.Helper()

	for _, file := range reader.File {
		if file.Method != zipMethodDeflate64 {
			continue
		}

		entryReader, err := file.Open()
		if entryReader != nil {
			_ = entryReader.Close()
		}
		if !errors.Is(err, zip.ErrAlgorithm) {
			t.Fatalf(
				"open unregistered method 9 entry: got %v want %v",
				err,
				zip.ErrAlgorithm,
			)
		}
		return
	}

	t.Fatalf("method 9 entry missing")
}

func readArchiveZIPEntries(t testing.TB, reader *zip.Reader) map[string][]byte {
	t.Helper()

	entries := make(map[string][]byte, len(reader.File))
	for _, file := range reader.File {
		entryReader, err := file.Open()
		if err != nil {
			t.Fatalf("open ZIP entry %s: %v", file.Name, err)
		}

		data, readErr := io.ReadAll(entryReader)
		closeErr := entryReader.Close()
		if readErr != nil {
			t.Fatalf("read ZIP entry %s: %v", file.Name, readErr)
		}
		if closeErr != nil {
			t.Fatalf("close ZIP entry %s: %v", file.Name, closeErr)
		}

		entries[file.Name] = data
	}

	return entries
}
