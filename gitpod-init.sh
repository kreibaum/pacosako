#!/bin/bash
# Init script for the gitpod container.
# This takes care of the workspace setup for you and will have already run
# for all prebuild workspaces.

# Setup pytrans.py
mkdir -p /home/gitpod/bin
curl -L -o /home/gitpod/bin/pytrans.py https://github.com/kreibaum/pytrans.py/releases/download/v0.0.3/pytrans.py
chmod +x /home/gitpod/bin/pytrans.py
export PATH="/home/gitpod/bin:$PATH"
echo "export PATH="/home/gitpod/bin:$PATH"" >> ~/.bashrc

# Setup cache_hash binary
curl -L -o /home/gitpod/bin/cache_hash https://github.com/kreibaum/pacosako/releases/download/v1.0.0-cache_hash/cache_hash
chmod +x /home/gitpod/bin/cache_hash

# Prepare target directory, prebuild frontend
echo Prebuild of elm frontend
mkdir -p target
cp frontend/static/* target/
cd frontend
pytrans.py
elm-spa build
elm make src/Main.elm --output=../target/elm.js
cd ..
# Supporting typescript code.
echo Prebuild of required typescript code
./scripts/compile-ts.sh

# Prepare database
echo Creating development database copy
cd backend
mkdir -p data
sqlx database create
sqlx migrate run
cd ..

# Prebuild server
# When I tried this, gitpod got stuck during prebuild.
# So you will just have to wait for the build when the server starts in the ide
# cd backend
# cargo build