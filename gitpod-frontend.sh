#!/bin/bash
# Opens a terminal where the frontend runs

cd frontend
elm-live src/Main.elm --no-server -- --output=../target/elm.js