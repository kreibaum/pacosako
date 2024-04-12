#!/bin/bash

# Compiles the library into a WebAssembly file.
# It then gets copied to the `target` folder.
# The javascript wrapper is also copied to the `target` folder and minified.
# Name of the wasm file is `lib.wasm`.
# Name of the javascript wrapper is `lib.js`.

# The `wasm-pack` tool is used to compile the library into a WebAssembly file.

# We need to use "no-modules" because we are using this in a WebWorker.
# Firefox does not support ES6 modules in WebWorkers yet.
# Supported by default with Firefox 114
# https://caniuse.com/mdn-api_worker_worker_ecmascript_modules

# Parse command line arguments for --fast option
FAST_MODE=0
for arg in "$@"
do
    if [ "$arg" = "--fast" ]; then
        FAST_MODE=1
    fi
done

mkdir -p build/frontend-wasm
mkdir -p target/js

# Set wasm-pack build command & brotli options based on fast mode
if [ $FAST_MODE -eq 1 ]; then
    echo "Running in fast mode..."
    WASM_PACK_OPTS="--dev --target no-modules"
    BROTLI_OPTS="-f --quality=0"
else
    WASM_PACK_OPTS="--release --target no-modules"
    BROTLI_OPTS="-f"
fi

wasm-pack build frontend-wasm $WASM_PACK_OPTS --out-name lib --out-dir ../build/frontend-wasm
cp build/frontend-wasm/lib_bg.wasm target/js/lib.wasm

# Minify the javascript wrapper.
echo "Minifying wasm wrapper javascript"
terser build/frontend-wasm/lib.js -o target/js/lib.min.js --compress --mangle

# Pre-compress both files with brotli
brotli $BROTLI_OPTS target/js/lib.wasm
brotli $BROTLI_OPTS target/js/lib.min.js
