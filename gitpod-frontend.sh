#!/bin/bash
# Opens a terminal where the frontend runs

cd frontend
# Enable English language
cp ./.elm-tflt/languages/en/Translations.elm ./.elm-tflt/linked/Translations.elm
elm-live src/Main.elm --no-server -- --output=../target/elm.js