# Compiles the typescript files and minifies them.

# Expects to be run from the / directory of the project
# Check if the "scripts" directory exists in the current directory as a proxy.
if [ ! -d "scripts" ]; then
    echo "This script must be run from the project root. Please change directory with cd."
    exit 1
fi

mkdir -p build/frontend-ts
mkdir -p target/js/

echo "Compiling Typescript"
tsc


# Define the input and output files
FILES_FOR_MAIN="./build/frontend-ts/static_assets.js ./build/frontend-ts/message_gen.js ./build/frontend-ts/main.js"
COMBINED_MAIN="./target/js/main.min.js"

# Check if the --dev argument is passed
if [ "$1" = "--dev" ]; then
    echo "Running in development mode: combining files without minification"
    cat $FILES_FOR_MAIN > $COMBINED_MAIN
    cat ./build/frontend-ts/lib_worker.js > ./target/js/lib_worker.min.js
else
    echo "Running in production mode: combining, mangling, and compressing files"
    terser $FILES_FOR_MAIN -o $COMBINED_MAIN --mangle --compress
    terser ./build/frontend-ts/lib_worker.js -o ./target/js/lib_worker.min.js --mangle --compress
fi

echo "Pre-compress compiled typescript with brotli"
brotli -f target/js/lib_worker.min.js
brotli -f target/js/main.min.js