FROM gitpod/workspace-full

USER gitpod

# Install custom tools, runtime, etc. using apt-get
# For example, the command below would install "bastet" - a command line tetris clone:
#
# RUN sudo apt-get -q update && #     sudo apt-get install -yq bastet && #     sudo rm -rf /var/lib/apt/lists/*
#
# More information: https://www.gitpod.io/docs/config-docker/

# SQLx command line utility for migration scripts.
RUN bash -cl "cargo install sqlx-cli"

# The frontend is using elm, this is not included in workspace-full
RUN bash -cl "npm install -g elm@latest-0.19.1 elm-live@next elm-format elm-spa@5.0.4 typescript uglify-js"
