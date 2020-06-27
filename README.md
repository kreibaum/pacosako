# Pacosako

This is the codebase for the pacoplay.com website. It has a frontend written in
[Elm](elm-lang.org) and a backend written in [Rust](rust-lang.org) based on the
Rocket server framework.

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

## Rules for Paco Ŝako (Rust Library)

Besides the server frontend in Elm and the backend in Rust, we also have a Rust
library which implements the rules of the game and provides some analysis
functions. Eventuall this library will also be included in the frontend via
Webassembler and Elm ports.

To run an example, just execute `cargo run`.

To build the webassembler file from the library run `wasm-pack build`.

See https://rustwasm.github.io/docs/book/game-of-life/hello-world.html for details on wasm.

## Deployment of the website

The website is currently running an an AWS container. Deployment is done
manually by Rolf at the moment. This Readme is just a convenient place to put
the documentation of deployment.

For the server

    cd backend
    cargo build --release
    # TODO: I probably need to adjust some paths or some config here, because index is loaded from ../target/index.html in the server code.
    scp -i ~/security/amazon-key-pair.pem ~/dev/pacosako/backend/target/release/pacosako-tool-server ubuntu@ec2-3-15-154-181.us-east-2.compute.amazonaws.com:~
    scp -i ~/security/amazon-key-pair.pem ~/dev/pacosako/backend/Rocket.toml ubuntu@ec2-3-15-154-181.us-east-2.compute.amazonaws.com:~
    scp -i ~/security/amazon-key-pair.pem ~/dev/pacosako/backend/data/* ubuntu@ec2-3-15-154-181.us-east-2.compute.amazonaws.com:~/data

For the frontend

    scp -i ~/security/amazon-key-pair.pem ~/dev/pacosako/target/* ubuntu@ec2-3-15-154-181.us-east-2.compute.amazonaws.com:~/target

To connect to the aws ec2 instance running the server with ssh, run

    ssh -i ~/security/amazon-key-pair.pem ubuntu@ec2-3-15-154-181.us-east-2.compute.amazonaws.com

When starting the server on port 8000, you need to set up a routing rule in the firewall

    iptables -t nat -I PREROUTING -p tcp --dport 80 -j REDIRECT --to-ports 8000
