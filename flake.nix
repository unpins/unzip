{
  description = "Info-ZIP unzip as a single self-contained binary";

  nixConfig = {
    extra-substituters = [ "https://unpins.cachix.org" ];
    extra-trusted-public-keys = [ "unpins.cachix.org-1:DDaShjbZ8VvcqxeTcAU3kV9vxZQBlyb7V/uLBHfTynI=" ];
  };

  inputs.unpins-lib.url = "github:unpins/nix-lib";

  # Info-ZIP unzip as one binary answering to unzip, funzip and zipinfo, folded
  # by the engine on every target. Windows builds Info-ZIP's own MinGW makefile
  # (./mingw.nix) with nixpkgs' patches.
  outputs = { self, unpins-lib }:
    let
      ulib = unpins-lib.lib;
      # `zipinfo` is an alias of unzip, which switches mode on its own name.
      programs = [
        { name = "unzip"; aliases = [ "zipinfo" ]; }
        { name = "funzip"; }
      ];
    in
    ulib.mkStandaloneFlake {
      inherit self;
      name = "unzip";
      # No winManRoot: each target curates its own man to the three shipped
      # pages (`build`'s postInstall, mingw.nix's installPhase), no graft.
      smoke = [ "-v" ];
      smokePattern = "Info-ZIP";

      # Build via the unpin-llvm engine + emit a bitcode multicall module. The
      # standalone self-folds unzip + funzip into one dispatcher binary from the
      # captured module.bc, Windows included.
      engine = "unpin-llvm";
      multicall = {
        inherit programs;
        windows = true;
      };
      build = pkgs:
        pkgs.pkgsStatic.unzip.overrideAttrs (o: {
          doCheck = pkgs.stdenv.buildPlatform.canExecute pkgs.stdenv.hostPlatform;
          # configure-c-crc.patch: the C CRC on every arch (the i386 asm's
          # table reference doesn't survive the engine's bitcode fold).
          patches = (o.patches or [ ]) ++ [ ./configure-c-crc.patch ];
          # Curate the embedded man to the three shipped applets. nixpkgs unzip
          # installs pages for unzipsfx (the self-extracting-archive stub) and
          # zipgrep (a /bin/sh wrapper) — neither of which we ship — so withMan
          # would embed them. Drop them; keep unzip/funzip/zipinfo, the set
          # mingw.nix installs.
          postInstall = (o.postInstall or "") + ''
            for _mo in $outputs; do
              rm -f "''${!_mo}/man/man1"/unzipsfx.1* "''${!_mo}/man/man1"/zipgrep.1* \
                    "''${!_mo}/share/man/man1"/unzipsfx.1* "''${!_mo}/share/man/man1"/zipgrep.1*
            done
          '';
        });
      windowsBuild = import ./mingw.nix { inherit ulib; };
    };
}
