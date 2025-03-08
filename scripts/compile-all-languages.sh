#!/bin/bash

cd frontend

# Run the i18n_gen command and process its output line by line
../backend/target/debug/i18n_gen --list | while IFS=$'\t' read -r name filename locale; do
  # Skip empty lines
  if [ -z "$name" ] ; then
    continue
  fi

  echo "Processing $name ($locale)..."

  # Generate the language-specific files
  ../backend/target/debug/i18n_gen "$name"

  # Create directories if they don't exist
  mkdir -p ../build/elm
  mkdir -p ../target/js

  # Compile Elm code with optimizations
  elm make src/Main.elm --optimize --output="../build/elm/elm.$locale.js"

  # Minify with Terser
  terser ../build/elm/elm."$locale".js -o ../target/js/elm."$locale".min.js --mangle --compress

  # Compress with Brotli
  brotli -f ../target/js/elm."$locale".min.js

  echo "Finished processing $name ($locale)."
done

echo "All languages processed."
