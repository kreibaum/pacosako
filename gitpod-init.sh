#!/bin/bash
# Init script for the gitpod container.
# This takes care of the workspace setup for you and will have already run
# for all prebuild workspaces.

# Prepare target directory, prebuild frontend
mkdir -p target
cp frontend/static/* target/
cd frontend
elm make src/Main.elm --output=../target/elm.js
cd ..

# Prebuild server
cd backend
cargo build