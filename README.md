# unzip

[Info-ZIP unzip](https://infozip.sourceforge.net/UnZip.html) as a single self-contained binary, built natively for Linux, macOS, and Windows.

[![CI](https://github.com/unpins/unzip/actions/workflows/unzip.yml/badge.svg)](https://github.com/unpins/unzip/actions)
![Linux](https://img.shields.io/badge/Linux-✓-success?logo=linux&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-✓-success?logo=apple&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-✓-success?logo=windows&logoColor=white)

Part of the [unpins](https://unpins.org) catalog; install it with [`unpin`](https://github.com/unpins/unpin): `unpin install unzip`.

## Usage

Run a program with [unpin](https://github.com/unpins/unpin):

```bash
unpin unzip archive.zip
unpin unzip zipinfo archive.zip
```

To install the programs onto your PATH:

```bash
unpin install unzip
```

`unpin install unzip` also creates the `funzip`, `zipinfo` commands.

## Man pages

The man pages for `unzip`, `funzip` and `zipinfo` are embedded in the binary;
read one with `unpin man unzip`, e.g. `unpin man unzip zipinfo`.
## Build locally

```bash
nix build github:unpins/unzip
./result/bin/unzip -v
```

Or run directly:

```bash
nix run github:unpins/unzip
```

The first invocation will offer to add the [unpins.cachix.org](https://unpins.cachix.org) substituter so most pulls come pre-built.

## Manual download

The [Releases](https://github.com/unpins/unzip/releases) page has standalone binaries for manual download.

## Build notes

- Single multicall binary. `funzip` (pipe filter) and `zipinfo` (archive
  listing) dispatch by `argv[0]`; `zipinfo` is served by `unzip` itself.
  Dropped: `zipgrep` (a `/bin/sh` wrapper) and `unzipsfx` (a self-extracting
  stub you concatenate with a zip — incompatible with a single binary).
- bzip2-compressed entries are supported (static libbz2 folded in).
- Built from the nixpkgs unzip, so the full upstream CVE-patch stack is included.
- **Windows** is built with [Cosmopolitan](https://github.com/jart/cosmopolitan)
  rather than mingw: Info-ZIP's `unix/Makefile` is Unix-only. (One Cosmopolitan
  fixup: force-include `<utime.h>` so timestamp restoration compiles.)

