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
      # The windows fold's whole dispatch table, declared once: ./multicall.nix
      # renders applets.list and the dispatcher from it, `withAliases` announces
      # it, and `multicall.windowsTable` hands the same value to CI. `zipinfo`
      # is an extra row at unzip's own main (unzip self-detects on argv[0]), and
      # `unzip` is in the table because the binary answers to it — which is also
      # what makes a bare `unzip.exe` extract instead of listing.
      programs = [
        { name = "unzip"; aliases = [ "zipinfo" ]; }
        { name = "funzip"; }
      ];
      winTable = ulib.multicallTableOf { name = "unzip"; inherit programs; };
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
        inherit programs;
        windowsTable = winTable;
      };
      # linux + darwin both self-fold through the engine (bitcode module), like
      # coreutils — no hand-rolled ld-r/objcopy fold (that recipe is ELF-only
      # and doesn't port to Mach-O). Windows still uses ./multicall.nix.
      build = pkgs:
        pkgs.pkgsStatic.unzip.overrideAttrs (o: {
          doCheck = pkgs.stdenv.buildPlatform.canExecute pkgs.stdenv.hostPlatform;
          # configure-c-crc.patch: the C CRC on every arch (the i386 asm's
          # table reference doesn't survive the engine's bitcode fold).
          patches = (o.patches or [ ]) ++ [ ./configure-c-crc.patch ];
          # Curate the embedded man to the three shipped applets. nixpkgs unzip
          # installs pages for unzipsfx (the self-extracting-archive stub) and
          # zipgrep (a /bin/sh wrapper) — neither of which we ship — so withMan
          # would embed them. Drop them; keep unzip/funzip/zipinfo. (The windows
          # multicall.nix already curates the same set.)
          postInstall = (o.postInstall or "") + ''
            for _mo in $outputs; do
              rm -f "''${!_mo}/man/man1"/unzipsfx.1* "''${!_mo}/man/man1"/zipgrep.1* \
                    "''${!_mo}/share/man/man1"/unzipsfx.1* "''${!_mo}/share/man/man1"/zipgrep.1*
            done
          '';
        });
      windowsBuild = import ./cosmo.nix { inherit ulib winTable; };
    };
}
