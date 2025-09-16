# Start from an official Rust image with stable toolchain
FROM rust:1.89-slim

# Install dependencies for SQLX, wasm-pack, Node, and Elm
RUN apt-get update && apt-get install -y \
    curl \
    build-essential \
    pkg-config \
    libssl-dev \
    nodejs \
    npm \
    git \
    brotli \
    && rm -rf /var/lib/apt/lists/*

# Install sqlx-cli for database migrations
RUN cargo install sqlx-cli --version ^0.5

# Install wasm-pack for WebAssembly builds
RUN curl https://rustwasm.github.io/wasm-pack/installer/init.sh -sSf | sh

# Install Elm, Elm SPA, TypeScript, and Terser globally
RUN npm install -g elm elm-spa@latest typescript terser --unsafe-perm=true --allow-root

# Set up a default working directory
WORKDIR /app

# Copy your source code here if you want to build inside the container
# COPY . .

# Default command (can be overridden in GitHub Actions)
CMD ["bash"]
