#!/bin/bash
source scripts/prelude.sh || exit 1

# Compiles the library into a WebAssembly file.
# It then gets copied to the `web-target` folder.
# The javascript wrapper is also copied to the `web-target` folder and minified.
# Name of the wasm file is `lib.wasm`.
# Name of the javascript wrapper is `lib.js`.

# The `wasm-pack` tool is used to compile the library into a WebAssembly file.

# We need to use "no-modules" because we are using this in a WebWorker.
# Firefox does not support ES6 modules in WebWorkers yet.
# Supported by default with Firefox 114
# https://caniuse.com/mdn-api_worker_worker_ecmascript_modules

# Set wasm-pack build options based on fast mode
if [ $FAST_MODE -eq 1 ]; then
    echo "Running in fast mode..."
    WASM_PACK_OPTS="--dev --target no-modules"
else
    WASM_PACK_OPTS="--release --target no-modules"
fi

wasm-pack build frontend-wasm $WASM_PACK_OPTS --out-name lib --out-dir ../web-build/frontend-wasm
cp web-build/frontend-wasm/lib_bg.wasm web-target/js/lib.wasm

# Minify the javascript wrapper.
echo "Minifying wasm wrapper javascript"
terser web-build/frontend-wasm/lib.js -o web-target/js/lib.min.js --compress --mangle

# Pre-compress both files with brotli
brotli $BROTLI_OPTS web-target/js/lib.wasm
brotli $BROTLI_OPTS web-target/js/lib.min.js
