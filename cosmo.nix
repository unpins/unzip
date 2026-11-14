# unzip for Windows-x86_64 via cosmocc, folded by ./multicall.nix.
{ ulib, winTable }:
pkgs:
let
  # unzip's unxcfg.h only pulls <utime.h> for linux/glibc/BSD4_4;
  # Cosmopolitan defines none of those, so utime()/struct utimbuf are
  # undeclared (gcc-14 errors). Cosmo ships <utime.h>, so force-include
  # it; also -DGOT_UTIMBUF so unzip's `ztimbuf` typedefs to the real
  # `struct utimbuf` (matching cosmo's utime() prototype) instead of its
  # own incompatible fallback struct. Cosmo compile only.
  cosmoUnzip = (ulib.cosmoStaticCross pkgs).unzip.overrideAttrs (old: {
    NIX_CFLAGS_COMPILE = (old.NIX_CFLAGS_COMPILE or "")
      + " -include utime.h -DGOT_UTIMBUF";
  });
in
import ./multicall.nix { lib = pkgs.lib // ulib; }
  { inherit pkgs winTable; unzip = cosmoUnzip; }
