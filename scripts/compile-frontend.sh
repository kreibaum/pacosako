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
scripts/compile-ts.sh
