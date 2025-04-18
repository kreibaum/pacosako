#!/bin/bash
source scripts/prelude.sh || exit 1

mkdir -p deploy/target
mkdir -p deploy/backend/templates
cp ./target/release/pacosako-tool-server ./deploy/backend/pacosako
cp ./backend/templates/* ./deploy/backend/templates
cp -r ./web-target/* ./deploy/target/
tar -zcf deploy.tar.gz deploy