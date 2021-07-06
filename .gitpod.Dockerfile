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
RUN bash -cl "npm install -g elm@latest-0.19.1 elm-live@next elm-format elm-spa@latest typescript uglify-js"

# I use a custom python script for translation management that is in a separate
# github project.
RUN curl -L -o /usr/local/bin/pytrans.py https://github.com/kreibaum/pytrans.py/releases/download/v0.0.1/pytrans.py
RUN chmod +x /usr/local/bin/pytrans.py