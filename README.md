# Pacosako

[![CI](https://github.com/kreibaum/pacosako/actions/workflows/main.yml/badge.svg)](https://github.com/kreibaum/pacosako/actions/workflows/main.yml)
<a href="https://hosted.weblate.org/engage/pacoplay/">
<img src="https://hosted.weblate.org/widgets/pacoplay/-/main-website/svg-badge.svg" alt="Translation status" />
</a>

This is the codebase for the [pacoplay.com website](http://pacoplay.com). It has a frontend written in
[Elm](https://elm-lang.org) and a backend written in [Rust](https://rust-lang.org) based on the
Rocket server framework.

If you want to help with the translation you can do so on our [Weblate](https://hosted.weblate.org/engage/pacoplay/) project:

<a href="https://hosted.weblate.org/engage/pacoplay/">
<img src="https://hosted.weblate.org/widgets/pacoplay/-/main-website/multi-auto.svg" alt="Translation status" />
</a>

If you want to help with development or are just interested in how the
website is build you can start a ready to code development environment in
your browser without any setup:

[![Gitpod Ready-to-Code](https://img.shields.io/badge/Gitpod-Ready--to--Code-blue?logo=gitpod)](https://gitpod.io/#https://github.com/kreibaum/pacosako)

Please not that you currently need to restart the backend server manually when
you make changes to rust code. The frontend is already recompiled automatically.

## Running without Gitpod

If you want to run the development environment locally, you will need to have
Rust, Elm and [elm-watch](https://github.com/lydell/elm-watch) installed.
You also need the latest version of [pytrans.py](https://github.com/kreibaum/pytrans.py/releases) on your path.

Then you run

    # Initialize target directory, copy static files
    ./gitpod-init.sh

    # Run elm-watch which keeps the frontend up to date & hot reloads
    cd frontend
    elm-watch hot

    # (In a second terminal) run the backend server:
    cd backend
    cargo run

## Rules for Paco Ŝako (Rust Library)

Besides the server frontend in Elm and the backend in Rust, we also have a Rust
library which implements the rules of the game and provides some analysis
functions. Eventually this library will also be included in the frontend via
webassembly and Elm ports.

To run an example, just execute `cargo run`.

To build the webassembly file from the library run `wasm-pack build`.

See https://rustwasm.github.io/docs/book/game-of-life/hello-world.html for details on wasm.

Note: WASM is a thing I want to use in the future but have not implemented
anything for yet. Having this in the readme is just a note to myself.

## Working on translations

Remember: if you just want to help with translations, use
[Weblate](https://hosted.weblate.org/engage/pacoplay/).

This part is for development. is switching the used language when programming.

If you want to merge translations that were done with weblate, use

    git remote add weblate https://hosted.weblate.org/git/pacoplay/main-website/
    git remote update weblate
    git merge weblate/main

Currently the translations are not integrated into the live reloading
development server. You can set the language you see the UI in by going into
the `frontend` folder and copying the right language version into position:

    # English
    pytrans.py English
    # Dutch
    pytrans.py Dutch
    # Esperanto
    pytrans.py Esperanto
    # Once you have chosen a language it is remembered any you can rebuild using
    pytrans.py

Once you copy this the dev server should pick up the change and recompile the
frontend for you.

## Working with Julia

To compile the shared library run `cargo build --release` in ./lib

Test if everything works

```
julia> using JtacPacoSako
julia> G = JtacPacoSako.PacoSako;
julia> model = Model.NeuralModel(G, Model.@chain G Dense(50, "relu"));
julia> player = Player.MCTSPlayer(model, power = 50, temperature=0);
julia> dataset = Player.record(player, 10, augment = false)
DataSet{PacoSako} with 1258 elements and 0 features
```

Play on the website

```julia
PacoPlay.play_match("https://dev.pacoplay.com", 212; player)
```

This assumes you have installed JtacPacoSako as a development package using

    ]dev ..../pacosako/julia

# Architecture

![A schematic drawing of the architecture when deployed.](/doc/architecture.png)