# Compiles the typescript files and minifies them.

# Expects to be run from the / directory of the project
# Check if the "scripts" directory exists in the current directory as a proxy.
if [ ! -d "scripts" ]; then
    echo "This script must be run from the project root. Please change directory with cd."
    exit 1
fi

mkdir -p build/frontend-ts

echo "Compiling Typescript"
tsc

echo "Minifying compiled Typescript"
terser ./build/frontend-ts/message_gen.js ./build/frontend-ts/main.js -o ./target/main.min.js --mangle --compress
terser ./build/frontend-ts/lib_worker.js -o ./target/lib_worker.min.js --mangle --compress