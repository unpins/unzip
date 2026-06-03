{
  description = "Standalone build of Info-ZIP unzip";

  nixConfig = {
    extra-substituters = [ "https://unpins.cachix.org" ];
    extra-trusted-public-keys = [ "unpins.cachix.org-1:DDaShjbZ8VvcqxeTcAU3kV9vxZQBlyb7V/uLBHfTynI=" ];
  };

  inputs.unpins-lib.url = "github:unpins/nix-lib";

  # Info-ZIP unzip: post-link `unzip` + `funzip` into one multicall binary
  # (`funzip`/`zipinfo` are argv[0]-dispatch UNPIN_META aliases; zipinfo is
  # served by unzip itself). See ./multicall.nix. Windows goes through
  # Cosmopolitan: the unix/Makefile is Unix-only (needs <sys/ioctl.h> etc.) and
  # the win32 makefile is a separate port. The nixpkgs unzip carries the full
  # CVE-patch stack, which we inherit.
  outputs = { self, unpins-lib }:
    let
      ulib = unpins-lib.lib;
    in
    ulib.mkStandaloneFlake {
      inherit self;
      name = "unzip";
      # No winManRoot: the shared multicall.nix installPhase curates the man to
      # the three shipped applets (unzip/funzip/zipinfo, dropping unzipsfx.1/
      # zipgrep.1) into $out/share/man on EVERY target — the cosmo .exe included
      # — so each build harvests its OWN man, no graft.
      smoke = [ "-v" ];
      smokePattern = "Info-ZIP";
      build = pkgs:
        import ./multicall.nix { lib = pkgs.lib // ulib; }
          {
            inherit pkgs;
            # unzip's i386 asm (crc_i386.S) omits the `.note.GNU-stack` marker,
            # so its objects request an executable stack. lld (the unpins
            # default linker, strict since 21) then aborts the i686 multicall
            # link with "requires an executable stack, but -z execstack is not
            # specified" — and an output `-z noexecstack` does NOT silence an
            # exec-stack INPUT. unzip never executes stack code, so assemble
            # with a non-exec GNU-stack note. Harmless on the asm-free arches.
            unzip = pkgs.pkgsStatic.unzip.overrideAttrs (o: {
              NIX_CFLAGS_COMPILE = (o.NIX_CFLAGS_COMPILE or "") + " -Wa,--noexecstack";
            });
          };
      windowsBuild = pkgs:
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
          { inherit pkgs; unzip = cosmoUnzip; };
    };
}
