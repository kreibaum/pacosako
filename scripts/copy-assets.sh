#!/bin/bash
source scripts/prelude.sh || exit 1

# Source directory
src_dir="frontend/static/"

# Destination directory
dst_dir="web-target/assets/"

# Output Elm file & ts file
elm_file="frontend/.asset-list/StaticAssets.elm"
ts_file="frontend/typescript/static_assets.ts"

# Create directories if they don't exist
mkdir -p "${dst_dir}"
mkdir -p "$(dirname "${elm_file}")"

# Start of the Elm file
echo "module StaticAssets exposing (..)" > "${elm_file}"
echo "-- This is a generated file with references to all static assets." >> "${elm_file}"
echo "" >> "${elm_file}"

echo "// This is a generated file with references to all static assets." > "${ts_file}"
echo "var static_assets: any = {};" >> "${ts_file}"

# Iterate over files in source directory
for src_file in "${src_dir}"*; do
    echo "Copying over ${src_file}"
    # Get the file name
    filename=$(basename "${src_file}")

    # Copy the file to the destination directory
    cp "${src_file}" "${dst_dir}${filename}"

    # Pre-compress with brotli
    brotli $BROTLI_OPTS "${dst_dir}${filename}"

    # Calculate the hash of the file
    hash=$(cache_hash "${src_file}")

    # Get the filename without the extension
    name_no_ext="${filename%.*}"

    # Append the file name and hash to the Elm file & ts file
    echo "${name_no_ext} : String" >> "${elm_file}"
    echo "${name_no_ext} = \"/a/${filename}?hash=${hash}\"" >> "${elm_file}"
    echo "" >> "${elm_file}"

    echo "static_assets.${name_no_ext} = \"/a/${filename}?hash=${hash}\"" >> "${ts_file}"
done
