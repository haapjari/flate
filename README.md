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

## Secret scanning

This repository is scanned with [gitleaks](https://github.com/gitleaks/gitleaks)
using the default ruleset in [`.gitleaks.toml`](.gitleaks.toml).

```sh
go install github.com/zricethezav/gitleaks/v8@latest
make setup-hooks
```

`make setup-hooks` enables the versioned hooks in `.githooks`. The pre-commit
hook scans staged changes and fails when gitleaks is not installed. The pre-push
hook refuses direct pushes to `main`.

`make verify-gitleaks` scans the full git history and the working tree. It is
part of `make verify` and also runs in CI.

The `main` branch is protected. Changes go through a pull request.

## License

This repository is derived from Go's standard library.

Go-derived code remains copyright The Go Authors and is licensed under the
BSD-style license in [`LICENSE`](LICENSE).

Project-specific modifications are distributed under the same BSD-style license
unless stated otherwise.

This project is not affiliated with or endorsed by Google LLC or the Go project.
