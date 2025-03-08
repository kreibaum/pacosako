# Expects to be run from the / directory of the project
# Check if the "scripts" directory exists in the current directory as a proxy.
if [ ! -d "scripts" ]; then
    echo "This script must be run from the project root. Please change directory with cd."
    exit 1
fi

mkdir -p target/js
mkdir -p target/assets

scripts/copy-assets.sh

scripts/compile-wasm.sh

cp frontend/static/* target/assets/
cd frontend || exit

# Codegen must happen before elm-spa builds
../backend/target/debug/i18n_gen
elm-spa build

cd .. || exit
# Iterate through all languages
scripts/compile-all-languages.sh

# Switch back to English, nice when running this manually in a dev environment.
cd frontend || exit
../backend/target/debug/i18n_gen English
cd .. || exit

# Typescript
scripts/compile-ts.sh