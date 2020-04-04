# Pacosako

[![Gitpod Ready-to-Code](https://img.shields.io/badge/Gitpod-Ready--to--Code-blue?logo=gitpod)](https://gitpod.io/#https://github.com/kreibaum/pacosako)

I am trying to set up a gitpod.io compatible version of my current pacosako project.

Paco Ŝako game website

## Running

If you are running this in gitpod, then the server should be started
automatically and the frontend will be rebuild when you save.

When running manually, follow those instructions

    # In one terminal, run elm-live to continuously rebuild the elm code
    cp frontend/static/* target/
    cd frontend
    elm-live src/Main.elm --no-server -- --output=../target/elm.js

    # In a second terminal, run the backend server
    # I'll include instructions when I add the backend to this repo.
