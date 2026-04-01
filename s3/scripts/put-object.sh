#!/usr/bin/env bash

if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: $0 <bucket-name> <file-path>"
  exit 1
fi

export AWS_CLI_AUTO_PROMPT=off

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Account ID: $ACCOUNT_ID"

REGION=$(aws configure get region)
echo "Region: $REGION"

BUCKET_NAME="${1}-${ACCOUNT_ID}-${REGION}-an"
FILE_PATH="$2"

echo "Uploading $FILE_PATH to bucket: $BUCKET_NAME"
aws s3api put-object \
  --bucket "$BUCKET_NAME" \
  --key "$(basename "$FILE_PATH")" \
  --body "$FILE_PATH"

export AWS_CLI_AUTO_PROMPT=on

echo "Done!"
