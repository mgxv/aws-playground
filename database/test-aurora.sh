#!/usr/bin/env bash
# test-aurora.sh — Connects to the Aurora cluster and runs sanity queries.
set -e

if [ ! -f ./aurora-info.env ]; then
    echo "ERROR: ./aurora-info.env not found. Run create-aurora.sh first."; exit 1
fi
source ./aurora-info.env

echo "Testing connection to $CLUSTER_ENDPOINT ..."
PGPASSWORD="$DB_PASSWORD" psql \
  "host=$CLUSTER_ENDPOINT port=5432 dbname=$DB_NAME user=$DB_USER sslmode=require" \
  -c "SELECT version();" \
  -c "SELECT current_database(), current_user;" \
  -c "\l"

echo ""
echo "✅ Connection successful!"
