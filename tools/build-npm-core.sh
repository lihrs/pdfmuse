#!/usr/bin/env bash
#
# Assemble the publishable `@pdfmuse/core` npm package from two wasm-pack builds.
#
# Why two builds: wasm-pack's `--target web` glue is ESM with an async
# `init(wasmBytes)` — unusable from a CommonJS `require()`. Plenty of Node hosts
# are CJS-only (bundled serverless runtimes, older Node), so we also ship the
# `--target nodejs` glue, which is CJS and instantiates the module synchronously
# at require time.
#
# Layout produced (single package, one shared .wasm):
#
#   package.json
#   pdfmuse_wasm.js        <- web/ESM glue      (import  → unchanged behavior)
#   pdfmuse_wasm.d.ts
#   pdfmuse_wasm.cjs       <- hand-written CJS entry (require → new)
#   pdfmuse_wasm_glue.cjs  <- nodejs/CJS glue, generated
#   pdfmuse_wasm.d.cts
#   pdfmuse_wasm_bg.wasm   <- shared by both; identity is asserted below
#
# The nodejs glue loads `${__dirname}/pdfmuse_wasm_bg.wasm`, so keeping it at the
# package root means no path patching of generated code. The CJS entry is a thin
# hand-written wrapper (crates/pdfmuse-wasm/node-entry.cjs) that installs a
# `crypto.getRandomValues` shim for Node < 19 before requiring the glue.
#
# Usage: tools/build-npm-core.sh [--out DIR]

set -euo pipefail

cd "$(dirname "$0")/.."

CRATE="crates/pdfmuse-wasm"
OUT="${CRATE}/pkg-dist"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) OUT="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

rm -rf "${CRATE}/pkg-web" "${CRATE}/pkg-node" "${OUT}"

echo "==> wasm-pack build --target web"
wasm-pack build "${CRATE}" --target web --release --out-dir pkg-web

echo "==> wasm-pack build --target nodejs"
wasm-pack build "${CRATE}" --target nodejs --release --out-dir pkg-node

# The two targets differ only in the JS glue; the wasm binary must be identical.
# If a future toolchain changes that, sharing one copy would silently ship the
# wrong module — so fail loudly instead.
echo "==> verifying the two builds emit an identical .wasm"
if ! cmp -s "${CRATE}/pkg-web/pdfmuse_wasm_bg.wasm" "${CRATE}/pkg-node/pdfmuse_wasm_bg.wasm"; then
  echo "ERROR: web and nodejs targets produced different .wasm binaries." >&2
  echo "       Ship them separately (node/ subdir) instead of sharing one copy." >&2
  exit 1
fi

# The nodejs glue must resolve the wasm relative to its own directory, which is
# what lets both entry points sit at the package root. Assert the assumption.
echo "==> verifying the nodejs glue loads the wasm via __dirname"
if ! grep -q '__dirname' "${CRATE}/pkg-node/pdfmuse_wasm.js"; then
  echo "ERROR: nodejs glue no longer resolves the wasm via __dirname." >&2
  echo "       Re-check the layout assumption in this script." >&2
  exit 1
fi

# A CJS consumer must get real named exports.
if ! grep -q '^exports\.parse' "${CRATE}/pkg-node/pdfmuse_wasm.js"; then
  echo "ERROR: nodejs glue does not export \`parse\` as CommonJS." >&2
  exit 1
fi

# The hand-written CJS entry shims `globalThis.crypto` for Node < 19 because the
# getrandom wasm_js backend reaches for it. If the glue ever stops needing it the
# shim is harmless, but if it starts needing something else this is where to look.
if grep -q 'globalThis\.crypto' "${CRATE}/pkg-node/pdfmuse_wasm.js"; then
  echo "==> nodejs glue uses globalThis.crypto — CJS entry shim applies"
fi

mkdir -p "${OUT}"
cp "${CRATE}/pkg-web/pdfmuse_wasm.js"          "${OUT}/pdfmuse_wasm.js"
cp "${CRATE}/pkg-web/pdfmuse_wasm.d.ts"        "${OUT}/pdfmuse_wasm.d.ts"
cp "${CRATE}/pkg-web/pdfmuse_wasm_bg.wasm"     "${OUT}/pdfmuse_wasm_bg.wasm"
cp "${CRATE}/pkg-web/pdfmuse_wasm_bg.wasm.d.ts" "${OUT}/pdfmuse_wasm_bg.wasm.d.ts"
cp "${CRATE}/pkg-node/pdfmuse_wasm.js"         "${OUT}/pdfmuse_wasm_glue.cjs"
cp "${CRATE}/node-entry.cjs"                   "${OUT}/pdfmuse_wasm.cjs"
cp "${CRATE}/pkg-node/pdfmuse_wasm.d.ts"       "${OUT}/pdfmuse_wasm.d.cts"
cp "${CRATE}/README.md"                        "${OUT}/README.md"
cp LICENSE-MIT LICENSE-APACHE                  "${OUT}/"

echo "==> writing package.json"
VERSION="$(node -e "process.stdout.write(require('./${CRATE}/pkg-web/package.json').version)")"
node - "$OUT" "$VERSION" <<'JS'
const fs = require('fs');
const [out, version] = process.argv.slice(2);

// `import` keeps resolving to the web/ESM build exactly as before — existing
// consumers (browsers, bundlers, Node ESM calling `await init(bytes)`) are
// untouched. Only the `require` condition is new.
const pkg = {
  name: '@pdfmuse/core',
  version,
  description:
    'Deterministic PDF/DOCX parser for RAG / LLMs — WebAssembly build (browser + Node).',
  license: 'MIT OR Apache-2.0',
  repository: { type: 'git', url: 'https://github.com/casperkwok/pdfmuse' },
  type: 'module',
  main: 'pdfmuse_wasm.cjs',
  module: 'pdfmuse_wasm.js',
  // Bundlers that ignore `exports` must never pick up the CJS glue (it uses `fs`).
  browser: 'pdfmuse_wasm.js',
  types: 'pdfmuse_wasm.d.ts',
  exports: {
    '.': {
      types: {
        require: './pdfmuse_wasm.d.cts',
        default: './pdfmuse_wasm.d.ts',
      },
      require: './pdfmuse_wasm.cjs',
      default: './pdfmuse_wasm.js',
    },
    './package.json': './package.json',
  },
  files: [
    'pdfmuse_wasm.js',
    'pdfmuse_wasm.d.ts',
    'pdfmuse_wasm.cjs',
    'pdfmuse_wasm_glue.cjs',
    'pdfmuse_wasm.d.cts',
    'pdfmuse_wasm_bg.wasm',
    'pdfmuse_wasm_bg.wasm.d.ts',
    'README.md',
    'LICENSE-MIT',
    'LICENSE-APACHE',
  ],
  sideEffects: ['./pdfmuse_wasm.cjs'],
  keywords: ['pdf', 'docx', 'rag', 'llm', 'wasm', 'parser', 'text-extraction'],
};

fs.writeFileSync(`${out}/package.json`, JSON.stringify(pkg, null, 2) + '\n');
JS

echo "==> ${OUT} ready"
ls -la "${OUT}"
