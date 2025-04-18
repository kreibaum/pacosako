#!/bin/bash
source scripts/prelude.sh || exit 1

scripts/copy-assets.sh

scripts/compile-wasm.sh

cp frontend/static/* target/assets/
cd frontend || exit

# Codegen must happen before elm-spa builds
i18n_gen
elm-spa build

cd .. || exit
# Iterate through all languages
scripts/compile-all-languages.sh

# Switch back to English, nice when running this manually in a dev environment.
cd frontend || exit
i18n_gen English
cd .. || exit

# Typescript
scripts/compile-ts.sh