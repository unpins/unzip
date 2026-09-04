# Changelog

## [Unreleased]

### Fixed

- On Windows, `--unpin-program=zipinfo` (and `funzip`) now selects that program.
  The previous binary ignored the option and ran `unzip` with it as an
  argument; only the installed command names worked.
