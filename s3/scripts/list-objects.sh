#!/usr/bin/env bash

if [ -z "$1" ]; then
  echo "Usage: $0 <bucket-name>"
  exit 1
fi

export AWS_CLI_AUTO_PROMPT=off

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Account ID: $ACCOUNT_ID"

REGION=$(aws configure get region)
echo "Region: $REGION"

BUCKET_NAME="${1}-${ACCOUNT_ID}-${REGION}-an"
echo "Listing files in bucket: $BUCKET_NAME"

aws s3api list-objects-v2 \
  --bucket "$BUCKET_NAME" \
  --query "Contents[].Key" \
  --output yaml

export AWS_CLI_AUTO_PROMPT=on

echo "Done!"
