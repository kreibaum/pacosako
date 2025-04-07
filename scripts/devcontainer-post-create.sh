#!/usr/bin/env bash

cd backend
cargo build --bin cache_hash --release
cargo build --bin i18n_gen --release

