
mkdir -p target
cp frontend/static/* target/
cd frontend
mkdir -p .elm-tflt/linked

# English is the default
cp ./.elm-tflt/languages/en/Translations.elm ./.elm-tflt/linked/Translations.elm
elm-spa build

# Iterate through all languages
# English
elm make src/Main.elm --output=../target/elm.en.js
# Dutch
cp ./.elm-tflt/languages/nl/Translations.elm ./.elm-tflt/linked/Translations.elm
elm make src/Main.elm --output=../target/elm.nl.js
# Esperanto
cp ./.elm-tflt/languages/eo/Translations.elm ./.elm-tflt/linked/Translations.elm
elm make src/Main.elm --output=../target/elm.eo.js
# Switch back to English, nice when running this manually in a dev environment.
cp ./.elm-tflt/languages/en/Translations.elm ./.elm-tflt/linked/Translations.elm

cd ..
# Typescript
tsc
# Minimize Javascript
uglifyjs ./target/elm.en.js -o ./target/elm.en.min.js --mangle --compress
uglifyjs ./target/elm.nl.js -o ./target/elm.nl.min.js --mangle --compress
uglifyjs ./target/elm.eo.js -o ./target/elm.eo.min.js --mangle --compress

uglifyjs ./target/main.js -o ./target/main.min.js --mangle --compress