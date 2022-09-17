
mkdir -p target
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

uglifyjs ./target/main.js -o ./target/main.min.js --mangle --compress