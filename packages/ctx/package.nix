{
  lib,
  fetchFromGitHub,
  flake,
  rustPlatform,
  installAgentSkills,
  versionCheckHook,
  versionCheckHomeHook,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "ctx";
  version = "2.3.0";

  src = fetchFromGitHub {
    owner = "ctxrs";
    repo = "ctx";
    tag = "v${finalAttrs.version}";
    hash = "sha256-XihSpW86eVALViD9mnSWXHldXI11T9N0uyHdlLXb9GU=";
  };

  # ctx allowlists Linux source-root filesystem magics and omits ZFS
  # (ctxrs/ctx#981), so every provider root on a ZFS home is rejected with
  # "provider source roots require a qualified local Linux filesystem".
  # Accept ZFS alongside the qualified local filesystems.
  # TODO: drop when upstream adds ZFS_SUPER_MAGIC.
  postPatch = ''
    substituteInPlace crates/ctx-history-source-io/src/io/root_handle/unix.rs \
      --replace-fail \
        'EXT_SUPER_MAGIC | XFS_SUPER_MAGIC | BTRFS_SUPER_MAGIC | F2FS_SUPER_MAGIC | TMPFS_MAGIC' \
        'EXT_SUPER_MAGIC | XFS_SUPER_MAGIC | BTRFS_SUPER_MAGIC | F2FS_SUPER_MAGIC | TMPFS_MAGIC | ZFS_SUPER_MAGIC'
    substituteInPlace crates/ctx-history-source-io/src/io/root_handle/unix.rs \
      --replace-fail 'const TMPFS_MAGIC: i64 = 0x0102_1994;' \
        'const TMPFS_MAGIC: i64 = 0x0102_1994;
    const ZFS_SUPER_MAGIC: i64 = 0x2FC1_2FC1;'
  '';

  cargoHash = "sha256-Jf51SQ7FuC9a55ZIFQlYW2ebsUGE62loiJHYoDVnu5Q=";

  cargoBuildFlags = [
    "--package"
    "ctx"
  ];

  # CoreML acquisition tests fail in Nix sandbox.
  doCheck = false;

  nativeBuildInputs = [ installAgentSkills ];

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  # The plugin tree contains another copy of the same skill.
  dontInstallAgentSkills = true;
  postInstall = ''
    installSkill skills/ctx
  '';

  postInstallCheck = ''
    test -f "$out/share/skills/ctx/ctx/SKILL.md"
  '';

  passthru.category = "Utilities";

  meta = {
    description = "Search the coding agent history already on your machine";
    homepage = "https://github.com/ctxrs/ctx";
    changelog = "https://github.com/ctxrs/ctx/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.asl20;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ mulatta ];
    mainProgram = "ctx";
    platforms = lib.platforms.unix;
  };
})
