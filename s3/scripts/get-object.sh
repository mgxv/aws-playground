#!/usr/bin/env bash

if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: $0 <bucket-name> <object-key>"
  exit 1
fi

# Disable auto-prompt
export AWS_CLI_AUTO_PROMPT=off

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Account ID: $ACCOUNT_ID"

REGION=$(aws configure get region)
echo "Region: $REGION"

BUCKET_NAME="${1}-${ACCOUNT_ID}-${REGION}"
OBJECT_KEY="$2"
DEST="./$(basename "$OBJECT_KEY")"
echo "Downloading s3://$BUCKET_NAME/$OBJECT_KEY to $DEST"

aws s3api get-object --bucket "$BUCKET_NAME" --key "$OBJECT_KEY" "$DEST"

# Re-enable auto-prompt
export AWS_CLI_AUTO_PROMPT=on

echo "Done!"
