# Pacosako

[![CI](https://github.com/kreibaum/pacosako/actions/workflows/main.yml/badge.svg)](https://github.com/kreibaum/pacosako/actions/workflows/main.yml)

This is the codebase for the [pacoplay.com website](http://pacoplay.com). It has a frontend written in
[Elm](https://elm-lang.org) and a backend written in [Rust](https://rust-lang.org) based on the
Rocket server framework.

If you want to help with development or are just interested in how the
website is build you can start a ready to code development environment in
your browser without any setup:

[![Gitpod Ready-to-Code](https://img.shields.io/badge/Gitpod-Ready--to--Code-blue?logo=gitpod)](https://gitpod.io/#https://github.com/kreibaum/pacosako)

Please not that you currently need to restart the backend server manually when
you make changes to rust code. The frontend is already recompiled automatically.

## Running without Gitpod

If you want to run the development environment locally, you will need to have
Rust, Elm and [elm-live](https://elm-live.com) installed. Then you run

    # Initialize target directory, copy static files
    ./gitpod-init.sh

    # Run elm-live which keeps the frontend up to date
    cd frontend
    elm-live src/Main.elm --no-server -- --output=../target/elm.js

    # (In a second terminal) run the backend server:
    cd backend
    cargo run

## Rules for Paco Ŝako (Rust Library)

Besides the server frontend in Elm and the backend in Rust, we also have a Rust
library which implements the rules of the game and provides some analysis
functions. Eventuall this library will also be included in the frontend via
Webassembler and Elm ports.

To run an example, just execute `cargo run`.

To build the webassembler file from the library run `wasm-pack build`.

See https://rustwasm.github.io/docs/book/game-of-life/hello-world.html for details on wasm.
