# Compiles the library into a WebAssembly file.
# It then gets copied to the `target` folder.
# The javascript wrapper is also copied to the `target` folder and minified.
# Name of the wasm file is `lib.wasm`.
# Name of the javascript wrapper is `lib.js`.

# The `wasm-pack` tool is used to compile the library into a WebAssembly file.

# We need to use "no-modules" because we are using this in a WebWorker.
# Firefox does not support ES6 modules in WebWorkers yet.

mkdir -p build/frontend-wasm
mkdir -p target/js

wasm-pack build frontend-wasm --target no-modules --out-name lib --out-dir ../build/frontend-wasm
cp build/frontend-wasm/lib_bg.wasm target/js/lib.wasm

# Minify the javascript wrapper.
echo "Minifying wasm wapper javascript"
terser build/frontend-wasm/lib.js -o target/js/lib.min.js --compress --mangle