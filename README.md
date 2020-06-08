# Pacosako

[![Gitpod Ready-to-Code](https://img.shields.io/badge/Gitpod-Ready--to--Code-blue?logo=gitpod)](https://gitpod.io/#https://github.com/kreibaum/pacosako)

I am trying to set up a gitpod.io compatible version of my current pacosako project.

Paco Ŝako game website

## Running

If you are running this in gitpod, then the server should be started
automatically and the frontend will be rebuild when you save.

In the future anyway, I have not configured that yet.

When running manually, follow those instructions

    # In one terminal, run elm-live to continuously rebuild the elm code
    mkdir target
    cp frontend/static/* target/
    cd frontend
    elm-live src/Main.elm --no-server -- --output=../target/elm.js

    # You currently need a sqlite database file to run the server.
    # Please just ask me for one until I get around to include a setup script
    # with the repository. It must be placed in ./backend/data/database.sqlite

    # In a second terminal, run the backend server
    cd backend
    cargo run
