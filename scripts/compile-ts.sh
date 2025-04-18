#!/bin/bash
source scripts/prelude.sh || exit 1
# Compiles the typescript files and minifies them.

echo "Compiling Typescript"
tsc


# Define the input and output files
COMBINED_MAIN="./web-target/js/main.min.js"

# Check if the --dev argument is passed
if [ "$1" = "--dev" ]; then
    echo "Running in development mode: combining files without minification"
    cat ./web-build/frontend-ts/static_assets.js ./web-build/frontend-ts/message_gen.js ./web-build/frontend-ts/main.js > $COMBINED_MAIN
    cat ./web-build/frontend-ts/lib_worker.js > ./web-target/js/lib_worker.min.js
else
    echo "Running in production mode: combining, mangling, and compressing files"
    terser ./web-build/frontend-ts/static_assets.js ./web-build/frontend-ts/message_gen.js ./web-build/frontend-ts/main.js -o $COMBINED_MAIN --mangle --compress
    terser ./web-build/frontend-ts/lib_worker.js -o ./web-target/js/lib_worker.min.js --mangle --compress
fi

echo "Pre-compress compiled typescript with brotli"
brotli $BROTLI_OPTS web-target/js/lib_worker.min.js
brotli $BROTLI_OPTS web-target/js/main.min.js