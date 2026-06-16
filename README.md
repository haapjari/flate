# Flate

This repository is a fork of Go's standard library
[`compress/flate`](https://cs.opensource.google/go/go/+/master:src/compress/flate/)
package.

It keeps the standard library implementation as the base and adds support for
reading raw Deflate64 streams.

## Background

This is a hobby project created while studying compression and experimenting
with extending Go's standard library `compress/flate` package.

The practical need came from a personal duplicate file cleaner tool that needed
to read Deflate64-compressed data.

Code changes in this repository were written with AI assistance.

## Deflate64

This fork adds `NewReader64`, which reads raw Deflate64 streams.

For ZIP files using method 9, it can be registered with `archive/zip`:

```go
zipReader.RegisterDecompressor(9, flate.NewReader64)
```

## License

This repository is derived from Go's standard library.

Go-derived code remains copyright The Go Authors and is licensed under the
BSD-style license in [`LICENSE`](LICENSE).

Project-specific modifications are distributed under the same BSD-style license
unless stated otherwise.

This project is not affiliated with or endorsed by Google LLC or the Go project.
