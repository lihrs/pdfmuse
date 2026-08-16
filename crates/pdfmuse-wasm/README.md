# @pdfmuse/core

WebAssembly build of [**pdfmuse**](https://github.com/casperkwok/pdfmuse) — a
deterministic PDF/DOCX parser for RAG / LLMs. No native binary: the same package runs
in the browser (the file never leaves the tab) and on Node, including CommonJS-only
hosts where a `.node` addon is not an option.

```bash
npm i @pdfmuse/core
```

## Usage

**Browser / ESM** — the wasm is fetched, so `init()` is async:

```js
import init, { to_text, parse } from "@pdfmuse/core";
await init();

const bytes = new Uint8Array(await file.arrayBuffer());
const text  = to_text(bytes);                  // plain reading-order text
const doc   = JSON.parse(parse(bytes));        // full IR: chars/blocks with bboxes
```

**Node / CommonJS** — the wasm is read from disk and instantiated at `require`
time, so there is no `init()` step:

```js
const { to_text, to_markdown, parse } = require("@pdfmuse/core");

const bytes = new Uint8Array(require("fs").readFileSync("resume.pdf"));
const md    = to_markdown(bytes);              // headings + tables preserved
```

**Node ≥ 18.** The module uses the `reference-types` and `multivalue` wasm
proposals, which Rust enables by default for `wasm32-unknown-unknown` and
current wasm-bindgen requires. Node 16 rejects it with `invalid value type
'externref'`, Node 14 with `return count of 4 exceeds internal limit of 1`.

Use this build when a native addon won't load — bundled serverless runtimes,
sandboxed platforms, anywhere the deploy artifact is JS-only. If you can ship a
binary, [`@pdfmuse/node`](https://www.npmjs.com/package/@pdfmuse/node) is faster.

Extracts text with exact coordinates, tables and structure; deterministic, byte-identical
to the Python/Node/Rust bindings. Scanned/image-only pages return a `NeedsOcr` warning to
hand off server-side.

- **Live playground:** https://casperkwok.github.io/pdfmuse/
- **Docs & source:** https://github.com/casperkwok/pdfmuse

MIT OR Apache-2.0
