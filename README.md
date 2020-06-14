# Pacosako

This is the codebase for the pacoplay.com website. It has a frontend written in
[Elm](elm-lang.org) and a backend written in [Rust](rust-lang.org) based on the Rocket server
framework.

If you want to help with development or are just interested in how the
website is build you can start a ready to code development environment in
your browser without any setup:

[![Gitpod Ready-to-Code](https://img.shields.io/badge/Gitpod-Ready--to--Code-blue?logo=gitpod)](https://gitpod.io/#https://github.com/kreibaum/pacosako)

Please not that you currently need to restart the backend server manually when
you make changes to rust code. The frontend is already recompiled automatically.

## Running without Gitpod

If you want to run the development environment locally, you will need to have
Rust, Elm and [elm-live](elm-live.com) installed. Then you run

    # Initialize target directory, copy static files
    ./gitpod-init.sh

    # Run elm-live which keeps the frontend up to date
    cd frontend
    elm-live src/Main.elm --no-server -- --output=../target/elm.js

    # (In a second terminal) run the backend server:
    cd backend
    cargo run
