{
  mnemosyne,
  buildPythonPackage,
  setuptools,
  wheel,
  pyyaml,
  pytest,
  python,
  pluginName ? "mnemosyne-memory",
  wrapperArgs ? [ ],
  extraDeps ? [ ],
}:

buildPythonPackage (finalAttrs: {
  pname = "mnemosyne-hermes";
  version = "0.3.1";
  src = mnemosyne.src;
  sourceRoot = "${finalAttrs.src.name}/integrations/hermes";
  pyproject = true;
  build-system = [
    setuptools
    wheel
  ];

  prePatch = ''
    substituteInPlace src/mnemosyne_hermes/plugin.yaml --replace-fail 'hermes-mnemosyne' '${pluginName}'
  '';

  dependencies = [
    mnemosyne
    pyyaml
  ]
  ++ extraDeps;

  makeWrapperArgs = wrapperArgs;
  nativeCheckInputs = [ pytest ];
  passthru.pluginDir = finalAttrs.finalPackage + "/${python.sitePackages}/mnemosyne-hermes";
  meta = {
    description = "Hermes integration for Mnemosyne";
    homepage = "https://github.com/mnemosyne-oss/mnemosyne";
  };
})
