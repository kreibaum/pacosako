# Expects to be run from the / directory of the project

mkdir -p target

scripts/compile-wasm.sh

cp frontend/static/* target/
cd frontend

# English is the default
pytrans.py English
elm-spa build

# Iterate through all languages
pytrans.py --run compile

# Switch back to English, nice when running this manually in a dev environment.
pytrans.py English

cd ..
# Typescript
tsc

terser ./target/main.js -o ./target/main.min.js --mangle --compress
terser ./target/lib_worker.js -o ./target/lib_worker.min.js --mangle --compress