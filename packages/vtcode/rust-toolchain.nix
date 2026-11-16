{
  lib,
  stdenv,
  fetchurl,
  patchelf,
  rustc,
  zlib,
}:

# VTCode requires this stable release before nixpkgs provides it.
let
  version = "1.100.0";
  target = stdenv.hostPlatform.rust.rustcTarget;
  hashes = {
    x86_64-linux = "sha256-mO5r7CQOHP6UTxfnCSQS3F724AhIS7ZoxpNtNafRWs0=";
    aarch64-linux = "sha256-oh9qIYGN8HweLnrdtXCvVESz+p3WHjogf0+xxaXmZck=";
    aarch64-darwin = "sha256-aLpyn+IN8PdDCe9V/75Rj8mCF38ydlGwYRLvEejh3g0=";
  };
in
stdenv.mkDerivation {
  pname = "rust-vtcode";
  inherit version;
  src = fetchurl {
    url = "https://static.rust-lang.org/dist/2026-11-12/rust-${version}-${target}.tar.xz";
    hash = hashes.${stdenv.hostPlatform.system};
  };
  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ patchelf ];
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    stdenv.cc.cc.lib
    zlib
  ];
  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;
  installPhase = ''
    runHook preInstall
    bash ./install.sh --prefix="$out" --disable-ldconfig \
      --components=rustc,rust-std-${target}
    runHook postInstall
  '';
  # LLVM's ELF layout cannot be rewritten by formatelf; patch this pinned toolchain explicitly.
  postFixup = lib.optionalString stdenv.hostPlatform.isLinux ''
    while IFS= read -r -d "" file; do
      if patchelf --print-rpath "$file" >/dev/null 2>&1; then
        patchelf --set-rpath "$out/lib:$out/lib/rustlib/${target}/lib:${
          lib.makeLibraryPath [
            stdenv.cc.cc.lib
            zlib
          ]
        }" "$file"
        if patchelf --print-interpreter "$file" >/dev/null 2>&1; then
          patchelf --set-interpreter "${stdenv.cc.bintools.dynamicLinker}" "$file"
        fi
      fi
    done < <(find "$out" -type f -print0)
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    "$out/bin/rustc" --version | grep -F 'rustc ${version}'
  '';
  passthru = {
    targetPlatforms = builtins.attrNames hashes;
    badTargetPlatforms = [ ];
  };
  meta = {
    description = "Pinned stable Rust toolchain for VTCode's minimum supported version";
    homepage = "https://www.rust-lang.org";
    changelog = "https://github.com/rust-lang/rust/releases/tag/${version}";
    inherit (rustc.meta) license maintainers;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "rustc";
    platforms = builtins.attrNames hashes;
  };
}
