# Compiles the library into a WebAssembly file.
# It then gets copied to the `target` folder.
# The javascript wrapper is also copied to the `target` folder and minified.
# Name of the wasm file is `lib.wasm`.
# Name of the javascript wrapper is `lib.js`.

# The `wasm-pack` tool is used to compile the library into a WebAssembly file.

# We need to use "no-modules" because we are using this in a WebWorker.
# Firefox does not support ES6 modules in WebWorkers yet.

cd lib
wasm-pack build --target no-modules --out-name lib --out-dir ../target
mv ../target/lib_bg.wasm ../target/lib.wasm

# Minify the javascript wrapper.

cd ../target
terser lib.js -o lib.min.js --compress --mangle