
mkdir -p target
cp frontend/static/* target/
cd frontend

# English is the default
pytrans.py English
elm-spa build

# Iterate through all languages
# English
pytrans.py English
elm make src/Main.elm --output=../target/elm.en.js
# Dutch
pytrans.py Dutch
elm make src/Main.elm --output=../target/elm.nl.js
# Esperanto
pytrans.py Esperanto
elm make src/Main.elm --output=../target/elm.eo.js
# Switch back to English, nice when running this manually in a dev environment.
pytrans.py English

cd ..
# Typescript
tsc
# Minimize Javascript
uglifyjs ./target/elm.en.js -o ./target/elm.en.min.js --mangle --compress
uglifyjs ./target/elm.nl.js -o ./target/elm.nl.min.js --mangle --compress
uglifyjs ./target/elm.eo.js -o ./target/elm.eo.min.js --mangle --compress

uglifyjs ./target/main.js -o ./target/main.min.js --mangle --compress