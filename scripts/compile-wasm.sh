# Compiles the library into a WebAssembly module.
# It then gets copied to the `target` folder.
# The javascript wrapper is also copied to the `target` folder and minified.
# Name of the wasm module is `lib.wasm`.
# Name of the javascript wrapper is `lib.js`.

# The `wasm-pack` tool is used to compile the library into a WebAssembly module.

cd lib
wasm-pack build --target web --out-name lib --out-dir ../target
mv ../target/lib_bg.wasm ../target/lib.wasm

# Minify the javascript wrapper.

cd ../target
terser lib.js -o lib.min.js --compress --mangle