FROM gitpod/workspace-full

USER gitpod

# Install custom tools, runtime, etc. using apt-get
# For example, the command below would install "bastet" - a command line tetris clone:
#
# RUN sudo apt-get -q update && #     sudo apt-get install -yq bastet && #     sudo rm -rf /var/lib/apt/lists/*
#
# More information: https://www.gitpod.io/docs/config-docker/

# Nightly rust is required by the Rocket server in version 0.4. We will switch
# to stable rust when Rocket 0.5 (async) releases.
RUN bash -cl "rustup default nightly"

# SQLx command line utility for migration scripts.
RUN bash -cl "cargo install --version=0.2.0 sqlx-cli"

# The frontend is using elm, this is not included in workspace-full
RUN bash -cl "npm install -g elm@latest-0.19.1 elm-live@next elm-format elm-spa@latest typescript uglify-js"