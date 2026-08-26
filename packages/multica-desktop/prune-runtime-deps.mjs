#!/usr/bin/env node
/**
 * Prune a pnpm workspace install down to the runtime closure of the built
 * Electron bundles.
 *
 * electron-vite bundles the renderer (out/renderer) fully and externalizes
 * every dependency in the main (out/main) and preload (out/preload)
 * bundles, so at runtime only the packages behind the `require()` externals
 * must be resolvable from node_modules. Everything else in the monorepo
 * store (two Next.js installs, expo/react-native, electron-builder, ...)
 * is dead weight for the desktop app.
 *
 * This script:
 *   1. scans out/main/*.js and out/preload/*.js for external require()
 *      specifiers (skipping Node builtins and the electron builtin),
 *   2. walks their transitive production-dependency closure through the
 *      installed workspace tree exactly the way Node resolves at runtime
 *      (nested node_modules, pnpm sibling links inside .pnpm, then hoisted
 *      fallbacks),
 *   3. copies the closure's .pnpm store entries into a target node_modules
 *      with pnpm's relative symlink layout intact and links the scanned
 *      roots at the top level,
 *   4. verifies the copied tree: every root resolves standalone, no
 *      dangling symlinks remain, and no ELF payloads are present (the
 *      runtime closure is pure JavaScript; a native module would need
 *      explicit packaging support instead of silent copying).
 *
 * Why not `pnpm deploy`: it requires inject-workspace-packages for the
 * workspace, re-runs lifecycle scripts (electron-builder
 * install-app-deps), and would ship every production dependency of the
 * renderer (@fontsource packs, motion, lucide-react, ...) that vite has
 * already bundled into out/renderer anyway.
 *
 * Usage: node prune-runtime-deps.mjs <workspace-root> <apps/desktop/out> <target-node_modules>
 */

import fs from "node:fs";
import path from "node:path";
import { createRequire, isBuiltin } from "node:module";

const [workspaceRootArg, outDirArg, targetArg] = process.argv.slice(2);
if (!workspaceRootArg || !outDirArg || !targetArg) {
  console.error(
    "usage: prune-runtime-deps.mjs <workspace-root> <out-dir> <target-node_modules>",
  );
  process.exit(2);
}

const workspaceRoot = path.resolve(workspaceRootArg);
const outDir = path.resolve(outDirArg);
const targetNm = path.resolve(targetArg);
const storeDir = path.join(workspaceRoot, "node_modules", ".pnpm");
const ELF_MAGIC = Buffer.from([0x7f, 0x45, 0x4c, 0x46]);
const desktopDir = path.join(workspaceRoot, "apps", "desktop");

function fail(message) {
  console.error(`prune-runtime-deps: ${message}`);
  process.exit(1);
}

/** Match `require("specifier")` / `require('specifier')` calls. */
const REQUIRE_RE =
  /\brequire\s*\(\s*(["'])((?:@[^/"']+\/)?[^"'.][^"']*)\1\s*\)/g;

function packageNameOf(specifier) {
  const parts = specifier.split("/");
  return specifier.startsWith("@")
    ? parts.slice(0, 2).join("/")
    : parts[0];
}

function scanExternals(bundleDirs) {
  const found = new Map(); // package name -> example specifier
  for (const dir of bundleDirs) {
    if (!fs.existsSync(dir)) {
      fail(`missing bundle directory ${dir} (was the app built?)`);
    }
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      if (!entry.isFile() || !entry.name.endsWith(".js")) continue;
      const source = fs.readFileSync(path.join(dir, entry.name), "utf8");
      let match;
      REQUIRE_RE.lastIndex = 0;
      while ((match = REQUIRE_RE.exec(source))) {
        const specifier = match[2];
        if (specifier === "electron" || isBuiltin(specifier)) continue;
        const name = packageNameOf(specifier);
        if (!found.has(name)) found.set(name, specifier);
      }
    }
  }
  return found;
}

/** Node-style package lookup: walk up from `fromDir` looking in
 *  `<dir>/node_modules/<name>`, without executing package entry points. */
function resolvePackageDir(fromDir, name) {
  let dir = fromDir;
  for (;;) {
    const candidate = path.join(dir, "node_modules", name);
    if (fs.existsSync(candidate)) return fs.realpathSync(candidate);
    const parent = path.dirname(dir);
    if (parent === dir) return null;
    dir = parent;
  }
}

/** Map a package directory to its node_modules/.pnpm/<key> store key. */
function storeKeyOf(packageDir) {
  const rel = path.relative(storeDir, packageDir);
  if (rel.startsWith("..") || path.isAbsolute(rel)) return null;
  return rel.split(path.sep)[0];
}

const externals = scanExternals([
  path.join(outDir, "main"),
  path.join(outDir, "preload"),
]);
if (externals.size === 0) {
  fail("no external require() found in built bundles — nothing to install");
}

const roots = new Map(); // package name -> store key
const closure = new Set(); // store keys
const visited = new Set(); // package dirs already walked

function walkPackage(packageDir) {
  const real = fs.realpathSync(packageDir);
  if (visited.has(real)) return;
  visited.add(real);

  const key = storeKeyOf(real);
  if (key) closure.add(key);
  else {
    fail(
      `transitive dependency ${real} resolves outside node_modules/.pnpm; ` +
        "workspace packages are not runtime dependencies of the bundle",
    );
  }

  const manifestPath = path.join(real, "package.json");
  if (!fs.existsSync(manifestPath)) {
    fail(`no package.json in ${real}`);
  }
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  const names = new Set([
    ...Object.keys(manifest.dependencies ?? {}),
    ...Object.keys(manifest.optionalDependencies ?? {}),
  ]);
  const optionalNames = new Set(
    Object.keys(manifest.optionalDependencies ?? {}),
  );

  for (const name of names) {
    const depDir = resolvePackageDir(real, name);
    if (!depDir) {
      if (optionalNames.has(name)) continue;
      fail(`dependency ${name} of ${real} not found in workspace install`);
    }
    walkPackage(depDir);
  }
}

for (const [name, specifier] of externals) {
  const dir = resolvePackageDir(desktopDir, name);
  if (!dir) {
    fail(
      `bundle external ${name} (require("${specifier}")) is not installed; ` +
        "if it is a false positive from the bundle scan, adjust the scanner",
    );
  }
  const key = storeKeyOf(dir);
  if (!key) {
    fail(
      `bundle external ${name} resolves outside ${storeDir} (${dir}); ` +
        "workspace packages are not runtime dependencies of the bundle",
    );
  }
  roots.set(name, key);
  walkPackage(dir);
}

/** cp -a semantics: symlinks verbatim, modes preserved, no dereference. */
function copyEntry(source, dest) {
  const stat = fs.lstatSync(source);
  if (stat.isSymbolicLink()) {
    fs.symlinkSync(fs.readlinkSync(source), dest);
  } else if (stat.isDirectory()) {
    fs.mkdirSync(dest, { recursive: true });
    for (const entry of fs.readdirSync(source)) {
      copyEntry(path.join(source, entry), path.join(dest, entry));
    }
  } else if (stat.isFile()) {
    fs.copyFileSync(source, dest);
    fs.chmodSync(dest, stat.mode);
  } else {
    fail(`unsupported entry type at ${source}`);
  }
}

fs.rmSync(targetNm, { recursive: true, force: true });
fs.mkdirSync(path.join(targetNm, ".pnpm"), { recursive: true });

let copiedFiles = 0;
let copiedBytes = 0;
for (const key of [...closure].sort()) {
  copyEntry(path.join(storeDir, key), path.join(targetNm, ".pnpm", key));
}

for (const [name, key] of roots) {
  const linkPath = path.join(targetNm, name);
  fs.mkdirSync(path.dirname(linkPath), { recursive: true });
  // Relative to the link's own directory (inside the scope folder for
  // scoped packages), matching the links pnpm itself creates.
  const linkTarget = path.relative(
    path.dirname(linkPath),
    path.join(targetNm, ".pnpm", key, "node_modules", name),
  );
  fs.symlinkSync(linkTarget, linkPath);
}

// The Electron runtime provides the `electron` module itself; drop the
// peer-dependency symlinks pointing at the workspace's devDependency copy.
function pruneElectronLinks(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      pruneElectronLinks(full);
    } else if (entry.isSymbolicLink() && entry.name === "electron") {
      fs.rmSync(full);
    }
  }
}
pruneElectronLinks(path.join(targetNm, ".pnpm"));

// Verification: no dangling symlinks, no ELF payloads, roots resolvable.
const dangling = [];
const elfFiles = [];
function verifyTree(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      verifyTree(full);
    } else if (entry.isSymbolicLink()) {
      if (!fs.existsSync(full)) dangling.push(path.relative(targetNm, full));
    } else if (entry.isFile()) {
      copiedFiles += 1;
      copiedBytes += fs.statSync(full).size;
      const fd = fs.openSync(full, "r");
      try {
        const header = Buffer.alloc(4);
        fs.readSync(fd, header, 0, 4, 0);
        if (header.equals(ELF_MAGIC)) elfFiles.push(path.relative(targetNm, full));
      } finally {
        fs.closeSync(fd);
      }
    }
  }
}
verifyTree(targetNm);

if (dangling.length > 0) {
  fail(`dangling symlinks in pruned tree:\n  ${dangling.join("\n  ")}`);
}
if (elfFiles.length > 0) {
  fail(
    "ELF payloads in pruned tree (native modules need explicit packaging " +
      `support):\n  ${elfFiles.join("\n  ")}`,
  );
}

for (const [name, specifier] of externals) {
  try {
    createRequire(path.join(path.dirname(targetNm), "__verify.js")).resolve(
      specifier,
    );
  } catch (error) {
    fail(`cannot resolve ${specifier} from pruned tree: ${error.message}`);
  }
}

console.log(
  `prune-runtime-deps: roots [${[...externals.keys()].sort().join(", ")}] ` +
    `${closure.size} store packages, ${copiedFiles} files, ` +
    `${(copiedBytes / 1024 / 1024).toFixed(1)} MiB -> ${targetNm}`,
);
