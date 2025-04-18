# This script is intended to be sourced from other scripts in the project.
# source scripts/prelude.sh || exit 1

## Check if we are running in the correct directory
ANCHOR_FILE="project-root-anchor.md"

if [[ ! -f "$ANCHOR_FILE" ]]; then
  echo "❌ Trying to run script from outside the project root. Please cd to the project root and try again." >&2
  return 1  # Return so the parent script can decide what to do (like exit)
fi

## Put the utilities in the PATH
TARGET_DIR="$PWD/target/release"

case ":$PATH:" in
  *":$TARGET_DIR:"*) : ;;  # already in PATH, do nothing
  *) export PATH="$TARGET_DIR:$PATH" ;;
esac

## Create directories if they don't exist
mkdir -p backend/data

mkdir -p web-build/elm
mkdir -p web-build/frontend-ts
mkdir -p web-build/frontend-wasm

mkdir -p web-target/js
mkdir -p web-target/assets


## Parse --fast command line argument for development mode
# Only parse if not already set
if [ -z "${FAST_MODE+x}" ]; then
  FAST_MODE=0
  for arg in "$@"; do
    if [ "$arg" = "--fast" ]; then
      FAST_MODE=1
    fi
  done
  export FAST_MODE
fi

## Set brotli options depending on fast mode
## Use with `brotli $BROTLI_OPTS <file>` to compress files
if [ "$FAST_MODE" -eq 1 ]; then
  BROTLI_OPTS="-f --quality=0"
else
  BROTLI_OPTS="-f"
fi

export BROTLI_OPTS