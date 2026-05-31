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
      pkgsX = unpins-lib.inputs.nixpkgs.legacyPackages.x86_64-linux;
      # The Windows binary's man comes from a graft of nixpkgs' unzip, whose
      # share/man carries all five pages (unzip/funzip/zipinfo + unzipsfx +
      # zipgrep). We ship only unzip/funzip/zipinfo, so pin a curated three-page
      # tree (the native side already curates its own man in the multicall
      # installPhase).
      winMan = pkgsX.runCommand "unzip-win-man" { } ''
        mkdir -p "$out/share/man/man1"
        for p in unzip funzip zipinfo; do
          zcat ${pkgsX.unzip}/share/man/man1/$p.1.gz > "$out/share/man/man1/$p.1"
        done
      '';
    in
    ulib.mkStandaloneFlake {
      inherit self;
      name = "unzip";
      winManRoot = winMan;
      smoke = [ "-v" ];
      smokePattern = "Info-ZIP";
      build = pkgs:
        import ./multicall.nix { lib = pkgs.lib // ulib; }
          { inherit pkgs; unzip = pkgs.pkgsStatic.unzip; };
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
