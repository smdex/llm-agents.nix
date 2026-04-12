{
  lib,
  stdenv,
  fetchzip,
  nodejs,
  makeWrapper,
}:

stdenv.mkDerivation rec {
  pname = "happier-relay-server";
  version = "0.2.0";

  src = fetchzip {
    url = "https://registry.npmjs.org/@happier-dev/relay-server/-/relay-server-${version}.tgz";
    hash = "sha256-phawkYrhSzd+SDTd+C6nXWHvcHT6nHUrt4JslKniFcY=";
  };

  nativeBuildInputs = [
    nodejs
    makeWrapper
  ];

  installPhase = ''
        runHook preInstall

        pkgDir="$out/lib/node_modules/@happier-dev/relay-server"
        mkdir -p "$pkgDir" "$out/bin"
        cp -r . "$pkgDir"

        for bin in happier-server relay-server happier-relay-server; do
          cat > "$out/bin/$bin" <<EOF
    #!${stdenv.shell}
    if [ "\''${1:-}" = "--help" ] || [ "\''${1:-}" = "-h" ]; then
      cat <<'USAGE'
    happier-server - official Happier relay server runner

    Usage:
      happier-server [--tag <release-tag>] [--ui-web-tag <release-tag>] [--no-ui-web] [server args...]

    This package wraps the upstream Node-based runner from @happier-dev/relay-server.
    At runtime it downloads and launches the matching Happier server release for your platform.
    USAGE
      exit 0
    fi
    exec ${nodejs}/bin/node "$pkgDir/bin/happier-server.mjs" "\$@"
    EOF
          chmod +x "$out/bin/$bin"
        done

        runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    ${nodejs}/bin/node --check "$out/lib/node_modules/@happier-dev/relay-server/bin/happier-server.mjs" >/dev/null
    runHook postInstallCheck
  '';

  passthru.category = "Utilities";

  meta = with lib; {
    description = "Official runner for the Happier self-hosted relay server";
    homepage = "https://github.com/happier-dev/happier";
    changelog = "https://github.com/happier-dev/happier/releases/tag/server-v${version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ binaryBytecode ];
    maintainers = with maintainers; [ ];
    mainProgram = "happier-server";
    platforms = platforms.all;
  };
}
