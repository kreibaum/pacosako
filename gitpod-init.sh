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
# When I tried this, gitpod got stuck during prebuild.
# So you will just have to wait for the build when the server starts in the ide
# cd backend
# cargo build