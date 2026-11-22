# Changelog

## [Unreleased]

### Changed

- unzip's `make check` now runs on every native build, so a regression fails
  the build instead of shipping.
- Windows: built with Info-ZIP's own MinGW port instead of Cosmopolitan.

## [6.0-2] - 2026-09-26

### Fixed

- On Windows, `--unpin-program=zipinfo` (and `funzip`) now selects that program.
  The previous binary ignored the option and ran `unzip` with it as an
  argument; only the installed command names worked.
