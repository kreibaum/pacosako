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
    git merge weblate/master

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

### Adding a new language

You first need a new language file in `frontend/i18n`. This can be
an empty dictionary `{}`. Once you sync that to weblate, weblate will allow
translators to translate the file.

When translations are available, merge changes from weblate into the main branch
as described above.

Add your language to `frontend/pytrans.json` to make it available to the Elm code.
Then run `pytrans.py` in the frontend directory. The `Translations.elm` file
is now updated and the Elm compiler should direct you to the next steps.

Afterwards you also need to update the `languageChoiceV2` function in `Header.elm`.

Note that locally switching language does't work with the buttons any instead you
need to run `pytrans.py Esperanto` or the equivalent for your language. This is
because the language is set at compile time so the app only has one language at a time.

In the backend you need to adapt the `get_static_language_file` function to make
sure the productive server is also able to deliver the compiled Elm in the right
language.

## Working with Julia

To compile the shared library run `cargo build --release` in ./lib

Test if everything works

```
julia> using JtacPacoSako
julia> G = JtacPacoSako.PacoSako;
julia> model = Model.NeuralModel(G, Model.@chain G Dense(50, "relu"));
julia> player = Player.MCTSPlayer(model, power = 50, temperature=0.1);
julia> dataset = Player.record(player, 10)
DataSet{PacoSako} with 1258 elements and 0 features
```

Play on the website

```julia
PacoPlay.play(player, color = :white, domain = :dev)
```

This assumes you have installed JtacPacoSako as a development package using

    ]dev ..../pacosako/julia

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

## Nginx Configuration

The application uses nginx to reverse proxy `dev.pacoplay.com` to the staging system and `pacoplay.com` to the production system. The nginx configuration file `nginx-config` is available in the `/scripts` directory. This configuration file should be placed in the `/etc/nginx/sites-available/` directory and a symbolic link to it should be created in the `/etc/nginx/sites-enabled/` directory on your server.

## Database Backups

The application automatically creates daily backups of the production SQLite database. These backups are created by a script named `create-backup.sh` which is run as a nightly cron job at 2 AM.

The `create-backup.sh` script performs the following actions:

1. Creates a backup of the `prod.sqlite` database located in `/home/pacosako/db/`.
2. Compresses the backup using `gzip`.
3. Deletes all but the five most recent backups.

The backups are saved in the `/home/pacosako/db/daily-backup/` directory, with each backup named as `prod-YYYYMMDDHHMM.sqlite.gz`, where `YYYYMMDDHHMM` is the date and time when the backup was created.

### Set Up The Backup Cron Job

To set up the backup cron job, run `crontab -e` and add the following line:

```cron
0 2 * * * /home/pacosako/create-backup.sh
```

This will run the `create-backup.sh` script every day at 2 AM.
