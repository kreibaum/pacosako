#!/bin/bash
# Opens a terminal where the frontend runs

cd frontend
# Enable English language
pytrans.py
elm-live src/Main.elm --no-server -- --output=../target/elm.js