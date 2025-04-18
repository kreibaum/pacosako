#!/bin/bash
source scripts/prelude.sh || exit 1

# Load environment variables from backend/.env
set -o allexport
source .env
set +o allexport

# Extract the file path from the DATABASE_URL (assuming sqlite)
DB_FILE="${DATABASE_URL#sqlite:}"

if [ -f "$DB_FILE" ]; then
  echo "The database already exists. Please delete it manually if you want to recreate it."
  exit 1
fi

sqlx database create || exit 1
sqlx migrate run --source backend/migrations || exit 1
