# Info-ZIP `unzip` ships several executables, but only two are distinct
# programs: `unzip` (extract; also serves `zipinfo` — zipinfo.o is part of
# unzip's object set and unzip dispatches on argv[0]) and `funzip` (filter a
# single member to stdout). The shipped `zipinfo` binary is literally a
# hardlink of `unzip`; `zipgrep` is a /bin/sh wrapper (dropped — needs an
# external shell + grep); `unzipsfx` is a self-extracting stub you concatenate
# with a zip, which is meaningless for a single multicall binary that already
# carries an appended unpin ZIP (dropped).
#
# So we post-link `unzip` + `funzip` into one multicall binary at
# $out/bin/unzip and expose `funzip` + `zipinfo` as argv[0]-dispatch UNPIN_META
# aliases (zipinfo routes to unzip's main, which self-detects via argv[0]).
#
# Same ld-r + prefix-rename recipe as zip/multicall.nix: the two programs share
# function names (globals.o vs globalsf.o, inflate.o vs inflatef.o, …) so a
# naive single link collides. Per tool we `ld -r` its objects into one partial
# object and `objcopy --redefine-syms` renames main → <tool>_main and every
# other strong global foo → <tool>__foo (objcopy rewrites defs AND the
# relocations that reference them), making each partial self-contained.
#
# bzip2 support is kept (`-DUSE_BZIP2`); the nixpkgs unzip derivation sets
# `NIX_LDFLAGS=-lbz2`, so the cc-wrapper folds static libbz2 into our final
# link automatically. Large-file support is already forced by the nixpkgs
# build (CF gets -DLARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64), so no extra flags.
#
# Shared by the native `build` (pkgsStatic ELF / Mach-O) and `windowsBuild`
# (Cosmopolitan APE) paths.
{ lib }:
{ pkgs, unzip }:
let
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin or false;
  isWindows = pkgs.stdenv.hostPlatform.isWindows or false;

  multicall = unzip.overrideAttrs (old: {
    pname = "unzip-multi";
    outputs = [ "out" ];
    installFlags = [ ];

    postBuild = (old.postBuild or "") + ''
      set -e
      mkdir -p multicall

      # CRCA_O (assembler-CRC object) is the one configure-variable object;
      # read it from the `flags` file unix/configure writes (empty on our
      # targets — C CRC). Everything else in OBJS/OBJF is static. M=unix.
      CRCA_O=""
      [ -f flags ] && CRCA_O=$(sed -n 's/.*CRCA_O="\([^"]*\)".*/\1/p' flags)

      declare -A TOOLOBJS
      TOOLOBJS[unzip]="unzip.o crc32.o $CRCA_O crypt.o envargs.o explode.o extract.o fileio.o globals.o inflate.o list.o match.o process.o ttyio.o ubz2err.o unreduce.o unshrink.o zipinfo.o unix.o"
      TOOLOBJS[funzip]="funzip.o crc32.o $CRCA_O cryptf.o globalsf.o inflatef.o ttyiof.o"
      TOOLS="unzip funzip"

      # Mach-O leads C symbols with '_'; detect once from unzip.o's `main`.
      if $NM --defined-only unzip.o 2>/dev/null | awk '$3=="_main"{f=1} END{exit !f}'; then
        up=_
      else
        up=""
      fi

      for t in $TOOLS; do
        real=""
        for o in ''${TOOLOBJS[$t]}; do
          if [ -f "$o" ]; then real="$real $o"
          else echo "multicall: $t object $o missing" >&2; exit 1; fi
        done
        $LD -r -o "multicall/$t.o" $real
        $NM --defined-only "multicall/$t.o" 2>/dev/null \
          | awk -v t="$t" -v up="$up" '
              $2 ~ /^[A-TX-Z]$/ && $2 != "W" && $2 != "V" {
                sym = $3
                core = sym
                if (up != "" && index(core, up) == 1) core = substr(core, 2)
                if (index(core, ".") != 0) next
                if (core !~ /^[A-Za-z_][A-Za-z0-9_]*$/) next
                if (core == "main") print sym " " up t "_main"
                else                print sym " " up t "__" core
              }' | sort -u > "multicall/$t.redef"
        [ -s "multicall/$t.redef" ] && \
          $OBJCOPY --redefine-syms="multicall/$t.redef" "multicall/$t.o"
      done

      # Dispatcher (shared canonical generator — see nix-lib
      # lib.multicallDispatcherC). apps.list carries the two real mains; `funzip`
      # matches as an applet, while `zipinfo` is NOT an applet — it falls through
      # to unzip (defaultApplet) with the original argv, so unzip's own argv[0]
      # self-detection still kicks in.
      printf '%s\n' $TOOLS > multicall/apps.list
${lib.multicallDispatcherC { name = "unzip"; defaultApplet = "unzip"; }}
      $CC -O2 -c -o multicall/dispatcher.o multicall/dispatcher.c

      # Final link: cc-wrapper adds -static (pkgsStatic/cosmo) and -lbz2
      # (NIX_LDFLAGS) automatically. One pass — partials are self-contained.
      $CC multicall/unzip.o multicall/funzip.o multicall/dispatcher.o \
        -o multicall/unzip
      [ -f multicall/unzip ] || mv multicall/unzip.exe multicall/unzip
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/bin" "$out/share/man/man1"
      install -m755 multicall/unzip "$out/bin/unzip"
      for a in funzip zipinfo; do ln -s unzip "$out/bin/$a"; done
      # Ship the man pages for the applets we expose (drop unzipsfx.1 / zipgrep.1
      # for the tools we don't carry).
      for m in unzip funzip zipinfo; do
        [ -f "man/$m.1" ] && cp "man/$m.1" "$out/share/man/man1/$m.1"
      done
      runHook postInstall
    '';
  });

  aliased = lib.withAliases pkgs
    {
      primary = "unzip";
      aliasesFromSymlinksIn = "bin";
    }
    multicall;
in
if isWindows
then aliased.overrideAttrs (o: {
  postFixup = (o.postFixup or "") + ''
    [ -f "$out/bin/unzip" ] && mv "$out/bin/unzip" "$out/bin/unzip.exe"
  '';
})
else aliased
