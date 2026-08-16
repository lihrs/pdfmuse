// CommonJS entry point for @pdfmuse/core (see tools/build-npm-core.sh).
//
// It exists to install one shim before the wasm-bindgen glue instantiates the
// module. The glue's getrandom backend calls `globalThis.crypto.getRandomValues`
// — a Web Crypto global that only exists from Node 19. On Node 14/16/18 (older
// LTS, and the Node version several serverless hosts pin) that call throws.
// Browsers are unaffected, which is why the generated glue assumes it.
//
// Hand-written on purpose: patching generated code in the build script would
// break silently the day wasm-bindgen reshapes that line.

if (
  typeof globalThis.crypto === 'undefined' ||
  typeof globalThis.crypto.getRandomValues !== 'function'
) {
  const nodeCrypto = require('crypto');
  const getRandomValues = (view) => {
    nodeCrypto.randomFillSync(view);
    return view;
  };

  if (typeof globalThis.crypto === 'object' && globalThis.crypto !== null) {
    // Node 15-18: `crypto.webcrypto` exists but the global doesn't carry
    // getRandomValues. Fill in just the missing method.
    try {
      globalThis.crypto.getRandomValues = getRandomValues;
    } catch {
      /* frozen — fall through to the defineProperty below */
    }
  }

  if (
    typeof globalThis.crypto === 'undefined' ||
    typeof globalThis.crypto.getRandomValues !== 'function'
  ) {
    Object.defineProperty(globalThis, 'crypto', {
      value: { getRandomValues },
      configurable: true,
      writable: true,
    });
  }
}

module.exports = require('./pdfmuse_wasm_glue.cjs');
