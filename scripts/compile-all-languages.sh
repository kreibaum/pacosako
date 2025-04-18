#!/bin/bash
source ./scripts/prelude.sh || exit 1

cd frontend

# Run the i18n_gen command and process its output line by line
i18n_gen --list | while IFS=$'\t' read -r name filename locale; do
  # Skip empty lines
  if [ -z "$name" ] ; then
    continue
  fi

  echo "Processing $name ($locale)..."

  # Generate the language-specific files
  i18n_gen "$name"

  # Compile Elm code with optimizations
  elm make src/Main.elm --optimize --output="../web-build/elm/elm.$locale.js"

  # Minify with Terser
  terser ../web-build/elm/elm."$locale".js -o ../web-target/js/elm."$locale".min.js --mangle --compress

  # Compress with Brotli
  brotli $BROTLI_OPTS ../web-target/js/elm."$locale".min.js

  echo "Finished processing $name ($locale)."
done

echo "All languages processed."
