// Acceptance check for the assembled @pdfmuse/core package.
//
// Installs the built package into a throwaway project and exercises BOTH entry
// points against a real PDF:
//
//   require('@pdfmuse/core')  -> CJS glue, synchronous instantiation
//   import  '@pdfmuse/core'   -> ESM glue, async init(bytes)   [unchanged path]
//
// Resolving through a real `npm install` is the point: it exercises the
// `exports` map exactly as a consumer would, which a direct file require does
// not. Run it before publishing — a broken `exports` map is invisible until
// someone installs the package.
//
// Usage: node tools/check-npm-core.mjs [pkgDir]

import { execFileSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, copyFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const repo = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const pkgDir = resolve(process.argv[2] ?? join(repo, 'crates/pdfmuse-wasm/pkg-dist'));
const corpus = join(repo, 'tests/corpus/hello.pdf');

const work = mkdtempSync(join(tmpdir(), 'pdfmuse-core-check-'));
const run = (cmd, args) =>
  execFileSync(cmd, args, { cwd: work, encoding: 'utf8', stdio: ['ignore', 'pipe', 'inherit'] });

try {
  copyFileSync(corpus, join(work, 'hello.pdf'));
  run('npm', ['init', '-y']);
  run('npm', ['install', '--no-audit', '--no-fund', pkgDir]);

  writeFileSync(
    join(work, 'cjs.cjs'),
    `const { parse, to_text, to_markdown } = require('@pdfmuse/core');
const bytes = new Uint8Array(require('fs').readFileSync('hello.pdf'));
const doc = JSON.parse(parse(bytes));
if (doc.source !== 'Pdf' || !doc.pages.length) throw new Error('bad IR: ' + JSON.stringify(doc).slice(0, 200));
if (!to_text(bytes).includes('Hello pdfmuse')) throw new Error('to_text lost content');
if (typeof to_markdown(bytes) !== 'string') throw new Error('to_markdown did not return a string');
console.log('  require() ok —', doc.pages.length, 'page(s)');
`
  );

  writeFileSync(
    join(work, 'esm.mjs'),
    `import init, { parse } from '@pdfmuse/core';
import { readFileSync } from 'node:fs';
await init({ module_or_path: readFileSync('./node_modules/@pdfmuse/core/pdfmuse_wasm_bg.wasm') });
const doc = JSON.parse(parse(new Uint8Array(readFileSync('hello.pdf'))));
if (doc.source !== 'Pdf' || !doc.pages.length) throw new Error('bad IR');
console.log('  import ok —', doc.pages.length, 'page(s)');
`
  );

  // Node < 19 has no `globalThis.crypto`, which the getrandom backend in the
  // glue reaches for. We cannot install Node 14 on every dev machine (no macOS
  // arm64 builds), so simulate the absence instead — this is what the CJS
  // entry's shim exists to survive.
  writeFileSync(
    join(work, 'no-webcrypto.cjs'),
    `Object.defineProperty(globalThis, 'crypto', { value: undefined, configurable: true, writable: true });
if (globalThis.crypto !== undefined) throw new Error('could not simulate a pre-Node-19 global');
const { parse } = require('@pdfmuse/core');
const doc = JSON.parse(parse(new Uint8Array(require('fs').readFileSync('hello.pdf'))));
if (doc.source !== 'Pdf' || !doc.pages.length) throw new Error('bad IR without globalThis.crypto');
if (typeof globalThis.crypto?.getRandomValues !== 'function') throw new Error('shim did not install getRandomValues');
console.log('  require() without globalThis.crypto ok —', doc.pages.length, 'page(s)');
`
  );

  console.log(`checking ${pkgDir}`);
  process.stdout.write(run('node', ['cjs.cjs']));
  process.stdout.write(run('node', ['esm.mjs']));
  process.stdout.write(run('node', ['no-webcrypto.cjs']));
  console.log('all entry points ok');
} finally {
  rmSync(work, { recursive: true, force: true });
}
