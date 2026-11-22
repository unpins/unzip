# unzip for windows-x86_64 through Info-ZIP's own MinGW makefile
# (win32/Makefile.gcc), with nixpkgs' patches. unzip and funzip are folded
# into one binary by the engine, as on the other targets.
{ ulib }:
pkgs:
let
  cross = pkgs.pkgsCross.mingwW64;
  prefix = cross.stdenv.hostPlatform.config;
in
cross.stdenv.mkDerivation {
  pname = "unzip";
  inherit (pkgs.unzip) version src;
  patches = pkgs.unzip.patches ++ [
    ./patches/mingw-windows-h-before-globals.patch
    ./patches/mingw-utf8-manifest.patch
  ];

  strictDeps = true;
  enableParallelBuilding = true;
  dontConfigure = true;

  makefile = "win32/Makefile.gcc";
  # NOASM: the crc_i386.S is 32-bit x86. CC_CPU_OPT drops -mcpu=pentiumpro.
  makeFlags = [
    "CC=${prefix}-gcc"
    "RC=${prefix}-windres"
    "NOASM=1"
    "CC_CPU_OPT="
  ];
  buildFlags = [ "unzip.exe" "funzip.exe" ];

  installPhase = ''
    runHook preInstall
    install -Dm755 -t $out/bin unzip.exe funzip.exe
    install -Dm644 -t $out/share/man/man1 man/unzip.1 man/funzip.1 man/zipinfo.1
    runHook postInstall
  '';

  passthru = { pname = "unzip"; inherit (pkgs.unzip) version; };
}
