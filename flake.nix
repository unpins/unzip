{
  description = "Info-ZIP unzip as a single self-contained binary";

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

      # Build via the unpin-llvm engine + emit a bitcode multicall module. The
      # standalone self-folds unzip + funzip into one dispatcher binary from the
      # captured module.bc; the old ld-r/objcopy fold in ./multicall.nix can't
      # run on the engine's -flto bitcode objects, so it's reserved for the
      # Windows (cosmo) path. Only `unzip` and `funzip` are real binaries —
      # `zipinfo` is unzip's argv[0] self-dispatch, so it's an alias of unzip.
      engine = "unpin-llvm";
      multicall = {
        programs = [
          { name = "unzip"; aliases = [ "zipinfo" ]; }
          { name = "funzip"; }
        ];
      };
      # linux + darwin both self-fold through the engine (bitcode module), like
      # coreutils — no hand-rolled ld-r/objcopy fold (that recipe is ELF-only
      # and doesn't port to Mach-O). Windows still uses ./multicall.nix.
      build = pkgs:
        pkgs.pkgsStatic.unzip.overrideAttrs (o: {
          # Force the C CRC on every arch. unzip's `generic` target runs
          # unix/configure, which on i386/i686 detects gas and selects the i386
          # CRC asm (sets `-DASM_CRC` + `CRCA_O=crc_gcc.o`). That asm's
          # `get_crc_table` reference doesn't resolve into the engine's bitcode
          # fold — the engine internalises the C table since only the external
          # asm uses it, so the i686 link dies with `undefined symbol:
          # get_crc_table`. Patch configure to never pick the asm: crc32.c then
          # supplies the C CRC + table, exactly as on every other arch (where the
          # crc_i386.S probe already fails, so this is a no-op). UNCONDITIONAL —
          # the engine builds i686 on an x86_64 host whose hostPlatform reports
          # neither i686 nor isLinux, so the i686 target can't be singled out, and
          # the C CRC is correct and harmless everywhere (incl. darwin, not i386).
          postPatch = (o.postPatch or "") + ''
            substituteInPlace unix/configure \
              --replace 'CRC32OA="crc_gcc.o"' 'CRC32OA=""' \
              --replace 'CFLAGSR="''${CFLAGSR} -DASM_CRC"' ':'
          '';
        } // pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
          # unzip's i386 asm omits the `.note.GNU-stack` marker, so its objects
          # request an executable stack; lld (strict since 21) then aborts an i686
          # link. Harmless on the asm-free arches; ELF-only, so the darwin/Mach-O
          # build skips it.
          NIX_CFLAGS_COMPILE = (o.NIX_CFLAGS_COMPILE or "") + " -Wa,--noexecstack";
        });
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
