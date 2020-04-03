FROM gitpod/workspace-full
                    
USER gitpod

# Install custom tools, runtime, etc. using apt-get
# For example, the command below would install "bastet" - a command line tetris clone:
#
# RUN sudo apt-get -q update && #     sudo apt-get install -yq bastet && #     sudo rm -rf /var/lib/apt/lists/*
#
# More information: https://www.gitpod.io/docs/config-docker/

# TODO: I'll need to install elm, I guess this is not available by default.
# I'll also need to switch to nightly rust to support Rocket
# And it seems like keyboard shortcuts don't work propperly yet with neo 2.

RUN bash -cl "rustup default nightly"