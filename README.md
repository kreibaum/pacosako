# Pacosako

[![CI](https://github.com/kreibaum/pacosako/actions/workflows/main.yml/badge.svg)](https://github.com/kreibaum/pacosako/actions/workflows/main.yml)
<a href="https://hosted.weblate.org/engage/pacoplay/">
<img src="https://hosted.weblate.org/widgets/pacoplay/-/main-website/svg-badge.svg" alt="Translation status" />
</a>

This is the codebase for the [pacoplay.com website](http://pacoplay.com). It has a frontend written in
[Elm](https://elm-lang.org) and a backend written in [Rust](https://rust-lang.org) based on the
Rocket server framework.

If you want to help with the translation, you can do so on our [Weblate](https://hosted.weblate.org/engage/pacoplay/)
project:

<a href="https://hosted.weblate.org/engage/pacoplay/">
<img src="https://hosted.weblate.org/widgets/pacoplay/-/main-website/multi-auto.svg" alt="Translation status" />
</a>

# Running the Project for Development

Sorry, this is a bit of a mess.

## Install Required Software

If you want to run the development environment locally, you will need to have installed:

- Rust, rustup, [wasm-pack](https://github.com/rustwasm/wasm-pack)
    - `cargo binstall wasm-pack`
- Elm and [elm-watch](https://github.com/lydell/elm-watch) and [elm-spa](https://www.elm-spa.dev/) (via npm)
- terser (via npm)
- brotli
- sqlx-cli (must be 0.5 :-/), e.g. via `cargo install sqlx-cli --version ^0.5`
- typescript (via npm)

For the npm packages, consider

- `sudo npm install -g elm elm-spa@latest typescript terser --unsafe-perm=true --allow-root`

If you want to work on the AI, you also need

- julia

And there is some work towards a python package as well

- python3

## Set up Database

The project uses SQLx for database access. You need to create a database before
it can compile the rust code.

```sh
scripts/setup-fresh-database.sh
```

If you are getting `error: error returned from database: disk I/O error` when
running this, check if maybe you deleted `database.sqlite` but kept around
the `database.sqlite-wal` and `database.sqlite-shm` files. If so, delete them.

## Fake a Secrets File

You can't get the real discord client secret, so you need to create a fake one.
We use Discord to manage logins so we don't have to deal with emails and account
recoveries.

```sh
echo 'discord_client_secret = ""' >> dev-secrets.toml
```

## Build everything

The project has a few internal development tools that you'll need to build.

```sh
cargo build --all --release
```

## Compile the Frontend

```sh
scripts/compile-frontend.sh
```

## Run the Project

### Run the backend

```sh
cd backend
cargo run
```

### Run the frontend

```sh
scripts/compile-frontend.sh
cd frontend
elm-watch hot
```

## Useful Software

Building WASM artifacts is faster, if you have wasm-bindgen installed:

    cargo install wasm-bindgen-cli

## Rules for Paco Ŝako (Rust Library)

Besides the server frontend in Elm and the backend in Rust, we also have a Rust
library which implements the rules of the game and provides some analysis
functions. Eventually, this library will also be included in the frontend via
webassembly and Elm ports.

To run an example, just execute `cargo run`.

To build the webassembly file from the library run the `scripts/compile-wasm.sh` script.
You also get this as part of `scripts/compile-frontend.sh` as well.

See https://rustwasm.github.io/docs/book/game-of-life/hello-world.html for details on wasm.

## Working on translations

Remember: if you just want to help with translations, use
[Weblate](https://hosted.weblate.org/engage/pacoplay/).

This part is for development. It is switching the used language when programming.

If you want to merge translations that were done with weblate, use

    git remote add weblate https://hosted.weblate.org/git/pacoplay/main-website/
    git remote update weblate
    git merge weblate/master

Currently, the translations are not integrated into the live reloading
development server. You can set the language you see the UI in by going into
the `frontend` folder and copying the right language version into position:

    # English
    ./backend/target/release/i18n_gen English
    # Dutch
    ./backend/target/release/i18n_gen Dutch
    # Esperanto
    ./backend/target/release/i18n_gen Esperanto
    # List all Languages
    ./backend/target/release/i18n_gen --list
    # Once you have chosen a language it is remembered any you can rebuild using
    ./backend/target/release/i18n_gen

Once you copy this, the dev server `elm-watch hot` should pick up the change and recompile the
frontend for you.

### Adding a new language

You first need a new language file in `frontend/i18n`. This can be
an empty dictionary `{}`. Once you sync that to weblate, weblate will allow
translators to translate the file.

When translations are available, merge changes from weblate into the main branch
as described above.

Add your language to `frontend/i18n-config.json` to make it available to the Elm code.
Then use `i18n_gen` in the frontend directory to switch to it.

Afterwards, you also need to update the `languageChoiceV2` function in `Header.elm`.

Note that locally switching language doesn't work with the buttons, and instead you
need to run `i18n_gen Esperanto` or the equivalent for your language. This is
because the language is set at compile time, so the app only has one language at a time.

In the backend you need to adapt the `get_static_language_file` function to make
sure the productive server is also able to deliver the compiled Elm in the right
language.

## Creating a username-password user

When developing the server without access to Discord secrets, you can create a
username-password user by inserting it directly into the database with

```sql
-- First, insert the user into the user table
INSERT INTO user (name, avatar)
VALUES ('Rolf Kreibaum', 'identicon:204bedcd9a44b3e1db26e7619bca694d');

-- Then, retrieve the ID of the newly inserted user and use it to insert into the login table
INSERT INTO login (user_id, type, identifier, hashed_password)
VALUES (last_insert_rowid(), 'password', 'rolf',
        '$argon2id$v=19$m=19456,t=2,p=1$OsG1y7Fvnq1FW8gKvlK4gQ$ryEgps/NG93d/Nyp8ri0GMR+LHymyb7ivnw5vnE4Q7U');
```

To get the `argon2` hash of a password, run the server locally
and try logging in with the password you want to use. The server will print
the hash to the console. (This happens only with `dev_mode = true`.)

Remember to commit the changes to the database.

# Working with Julia

To load JtacPacoSako, do the following:

```julia
# Load CUDA and cuDNN
julia> # using Revise (Only for development)
julia> using cuDNN
julia> using JtacPacoSako
```

To compile the shared library run `cargo build --release` in ./lib

This assumes you have installed Jtac.jl and JtacPacoSako as a development package using

    ]dev {..}/Jtac.jl
    ]dev {..}/pacosako/julia

Test if everything works

```
julia> G = PacoSako;
julia> model = Model.NeuralModel(G, Model.@chain G Dense(50, "relu"));
julia> player = Player.MCTSPlayer(model, power = 50, temperature=0.1);
julia> dataset = Training.record(player, 10)
DataSet{PacoSako} with 1258 elements and 0 features
```

## Loading Models

Models can be used from various sources. If you just want to play with an
existing model, you can get it by its name from our artifact storage:

The artifact system is hosted at https://static.kreibaum.dev/

```julia
# Get the Default model for Ludwig:
model = Ludwig()
# Get a specific version of Ludwig, make it run on the GPU:
model = Ludwig("1.0-human", async=false, backend=:cuda)
```

If you already have a specific model downloaded, you can load it from a file:

```julia
model = Model.load("models/ludwig-1.0.jtm", async=false, backend=:cuda)
```

## Using models

To apply a model to a single game state, use `Model.apply`:

```julia
model = Ludwig()
state = PacoSako()
Model.apply(model, state)
```

Turn the model into a player:

```julia
player = Player.MCTSPlayer(model, power = 3000, temperature=0.01)
```

Play on the website

```julia
PacoPlay.play(player, color = :white, domain = :dev)
```

Or to connect to the official server with a username and password

```julia
PacoPlay.play(player, color = :white, domain = :official, username = "ludwig_ai", password = "hunter2")
```

## Errors you may encounter

```plaintext
julia> model = Ludwig("1.0-human", async=false, backend=:cuda)
ERROR: CUDA initialization failed: CUDA error (code 999, CUDA_ERROR_UNKNOWN)
```

This may happen when you suspend your computer while the CUDA driver is still
loaded. To fix this, you must restart your computer.

# Working with Python

We have a Python package that can be used to interact with the Rust library.
It is there to support some statistical analysis Bas has been doing.

You'll need `maturin` from the pyo3 ecosystem: https://pyo3.rs/

Then you need to got to `/python` to build the package:

```bash
maturin build --release
```

Afterward, you can install the package with pip:

```bash
pip install target/wheels/pacosako-$LOOK_IT_UP.whl
```

When you are just developing the package, you can use the `develop` command:

```bash
maturin develop --release
```

# Replay Meta Data

It is possible to attach arbitrary json metadata to a replay.
This requires you to have access to an AI users api credentials.

Every piece of metadata is associated with a game and an action index. It is
also sorted into a category. The category is just an arbitrary string
shown in the frontend to group metadata together and to control what is shown.

Of course, the frontend has no way to render arbitrary metadata. So you need to
conform to an implemented schema. Here is what we currently support:

```jsonc
{
  "type": "arrow",
  "tail": 11,
  "head": 27,
  "color": "#ffc80080", // Optional, default #ffc80080
  "width": 20 // Optional, default 10
  // "width" may also be replaced by "weight" which scales arrows proportionally
}
```

Additionally, we are also planning to implement

```jsonc
{
  "type": "value",
  "value": 0.38,
  "impact": -0.09, // Optional
  "best": 0.02, // Optional
  "rank": 3, // Optional
  "rank_of": 10 // Optional
}
```

# Architecture

![A schematic drawing of the architecture when deployed.](/doc/architecture.png)

# Deployment and Server Management

This application is set up to run using two systemd services, one for the staging environment and one for
the production environment. The configuration for these services is available in the `/scripts` directory.

## Systemd Services

The systemd service files are:

- `stage.service`: This service runs the staging server.
- `prod.service`: This service runs the production server.

These service files should be placed in the `/etc/systemd/system/` directory on your server.

To control the services, you can use the following commands:

- Start the service: `sudo systemctl start servicename`
- Stop the service: `sudo systemctl stop servicename`
- Enable the service to start on boot: `sudo systemctl enable servicename`
- Disable the service from starting on boot: `sudo systemctl disable servicename`
- Check the status of the service: `sudo systemctl status servicename`

Replace `servicename` with either `stage` or `prod` depending on which service you want to control.

## Update Scripts

There are two scripts used to update the staging and production servers:

- `update-stage.sh`: This script is used to deploy a new version to the staging server.
  It first stops the staging service, removes the existing deployment, installs the new deployment,
  and then restarts the staging service.
- `update-prod.sh`: This script is used to promote the staging version to production.
  It first stops the production service, backs up the current production server and database,
  removes the existing deployment, installs the new deployment from staging,
  and then restarts the production service.

Each server will update its own database schema when it starts up.

## Caddy Configuration

The application uses caddy to reverse proxy `dev.pacoplay.com` to the staging system and `pacoplay.com` to the
production system.
The `Caddyfile` is available in the `/scripts` directory. This configuration file should be placed in the `/etc/caddy/`
directory.

## Database Backups

The application automatically creates daily backups of the production SQLite database. These backups are created by a
script named `create-backup.sh` which is run as a nightly cron job at 2 AM.

The `create-backup.sh` script performs the following actions:

1. Creates a backup of the `prod.sqlite` database located in `/home/pacosako/db/`.
2. Compresses the backup using `gzip`.
3. Deletes all but the five most recent backups.

The backups are saved in the `/home/pacosako/db/daily-backup/` directory, with each backup named
as `prod-YYYYMMDDHHMM.sqlite.gz`, where `YYYYMMDDHHMM` is the date and time when the backup was created.

### Set Up The Backup Cron Job

To set up the backup cron job, run `crontab -e` and add the following line:

```cron
0 2 * * * /home/pacosako/create-backup.sh
```

This will run the `create-backup.sh` script every day at 2 AM.

# Papers and other references

This isn't a complete overview, but I wanted a central place to collect the references that I know about.

## Auxiliary Policy Targets

[Accelerating Self-Play Learning in Go](https://arxiv.org/abs/1902.10565)

> As another generalizable improvement over AlphaZero, we add an auxiliary policy target that predicts the
> opponent’s reply on the following turn to improve regularization.

