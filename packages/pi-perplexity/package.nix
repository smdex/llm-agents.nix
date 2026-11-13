{
  lib,
  flake,
  stdenvNoCC,
  bun,
  fetchFromGitHub,
  versionCheckHook,
}:
let
  hashes = lib.importJSON ./hashes.json;
  version = hashes.version;
  src = fetchFromGitHub {
    owner = "smdex";
    repo = "pi-perplexity";
    inherit (hashes) rev hash;
  };
  bunDeps = stdenvNoCC.mkDerivation {
    pname = "pplx-bun-deps";
    inherit version;
    src = src;
    nativeBuildInputs = [ bun ];
    buildPhase = ''
      export HOME=$TMPDIR XDG_CACHE_HOME=$TMPDIR/xdg-cache
      bun install --frozen-lockfile --production --ignore-scripts --no-progress
    '';
    installPhase = ''
      mkdir -p $out
      cp -R node_modules $out/node_modules
    '';
    dontFixup = true;
    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
    outputHash = hashes.bunDepsHash;
  };
in
stdenvNoCC.mkDerivation {
  pname = "pplx";
  inherit version;
  src = src;
  nativeBuildInputs = [ bun ];
  buildPhase = ''
    cp -R ${bunDeps}/node_modules ./node_modules
    chmod -R u+w node_modules
    export HOME=$TMPDIR XDG_CACHE_HOME=$TMPDIR/xdg-cache
    bun build --target=bun --minify --outfile=pplx.js ./src/index.ts
  '';
  installPhase = ''
    install -Dm644 pplx.js $out/lib/pplx/pplx.js
    install -Dm755 pplx.js $out/bin/pplx
    patchShebangs $out/bin/pplx
    install -Dm644 ${src}/skills/perplexity-cli/SKILL.md $out/share/pplx/skills/perplexity-cli/SKILL.md
  '';
  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];
  passthru.category = "Utilities";
  passthru.bunDeps = bunDeps;
  meta = {
    description = "Perplexity CLI for cited answers, research, and threads";
    homepage = "https://github.com/smdex/pi-perplexity";
    changelog = "https://github.com/smdex/pi-perplexity/releases/tag/v0.6.1";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "pplx";
    platforms = lib.platforms.all;
  };
}
