#!/bin/bash
source scripts/prelude.sh || exit 1

# This script build a package that may be used to deploy the application to a server.
# It uses the artifacts that have been previously built. This means that the
# server should be using the same libc version as the one used to build the artifacts.
# E.g. if your build pipeline uses ubuntu 24.04 and the server uses ubuntu 20.04,
# the artifact can't be used.

mkdir -p deploy/target
mkdir -p deploy/backend/templates
cp ./target/release/pacosako-tool-server ./deploy/backend/pacosako
cp ./backend/templates/* ./deploy/backend/templates
cp -r ./web-target/* ./deploy/target/
tar -zcf deploy.tar.gz deploy