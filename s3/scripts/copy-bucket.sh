#!/usr/bin/env bash

if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: $0 <source-bucket> <destination-bucket>"
  exit 1
fi

export AWS_CLI_AUTO_PROMPT=off

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Account ID: $ACCOUNT_ID"

REGION=$(aws configure get region)
echo "Region: $REGION"

SOURCE_BUCKET="${1}-${ACCOUNT_ID}-${REGION}-an"
DEST_BUCKET="${2}-${ACCOUNT_ID}-${REGION}-an"

echo "Copying from: $SOURCE_BUCKET"
echo "Copying to: $DEST_BUCKET"

aws s3 sync s3://"$SOURCE_BUCKET" s3://"$DEST_BUCKET"

export AWS_CLI_AUTO_PROMPT=on

echo "Done!"
