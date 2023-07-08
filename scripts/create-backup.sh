#!/bin/bash

# This creates a timestamped backup of the SQLite database and compresses it.
# Example name: ~/db/daily-backup/prod-202307030200.sqlite.gz
# It also deletes all but the 5 most recent backups.

# Set variables
DATABASE="/home/pacosako/db/prod.sqlite"
BACKUP_DIR="/home/pacosako/db/daily-backup"
TIMESTAMP=$(date +"%Y%m%d%H%M")
BACKUP_FILE="${BACKUP_DIR}/prod-${TIMESTAMP}.sqlite"
COMPRESSED_FILE="${BACKUP_FILE}.gz"

# Create backup directory if it doesn't exist
mkdir -p "${BACKUP_DIR}"

# Create a backup of the SQLite database
/usr/bin/sqlite3 "${DATABASE}" ".backup '${BACKUP_FILE}'"

# Compress the backup
gzip "${BACKUP_FILE}"

# Delete all but the 5 most recent backups

## The ls -t command lists all files in the directory, sorted by modification time,
## with the newest files first. The sed -e '1,5d' command deletes the first 5 lines
## from the output, which correspond to the five most recent files.
## The xargs -d '\n' rm command deletes the files that are listed in the remaining lines.
## The -r flag prevents xargs from running if there are no input lines (less than 5 files.)

cd "${BACKUP_DIR}"
ls -t | sed -e '1,5d' | xargs -d '\n' -r rm
