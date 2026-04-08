#!/usr/bin/env bash

if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: $0 <source-dir> <bucket-name>"
  exit 1
fi

export AWS_CLI_AUTO_PROMPT=off

SOURCE_DIR="$1"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Account ID: $ACCOUNT_ID"

REGION=$(aws configure get region)
echo "Region: $REGION"

BUCKET_NAME="${2}-${ACCOUNT_ID}-${REGION}"
echo "Syncing $SOURCE_DIR to bucket: $BUCKET_NAME"

aws s3 sync "$SOURCE_DIR" s3://"$BUCKET_NAME"

export AWS_CLI_AUTO_PROMPT=on

echo "Done!"
