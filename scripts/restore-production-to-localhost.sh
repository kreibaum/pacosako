#!/bin/bash

# This utility allows me (Rolf) to restore a production copy into my local
# development environment. It is not intended for use by anyone else.
# The nightly backups are automatically downloaded by a cron job.

# Directory to check
backup_dir="/home/rolf/dev/pacosako-common/pacoplay-backup"
# Target directory
target_dir="/home/rolf/dev/pacosako/backend/data"

# Check if backup directory exists
if [ ! -d "$backup_dir" ]; then
    echo "Backup directory does not exist: $backup_dir"
    exit 1
fi

# Check if any process is listening on port 8000
if lsof -i:8000; then
    echo "A process is listening on port 8000. Please stop it before proceeding."
    exit 1
fi

# Find the newest file matching the pattern
newest_file=$(ls -t $backup_dir/prod-*.sqlite.gz | head -n 1)

if [ -z "$newest_file" ]; then
    echo "No matching files found in $backup_dir"
    exit 1
fi

# Clean up existing data
rm -f $target_dir/database.sqlite
rm -f $target_dir/database.sqlite-shm
rm -f $target_dir/database.sqlite-wal

# Copy and unzip the file
cp "$newest_file" "$target_dir/database.sqlite.gz"
gunzip "$target_dir/database.sqlite.gz"

echo "Database updated successfully."
