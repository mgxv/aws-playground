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

BUCKET_NAME="${1}-${ACCOUNT_ID}-${REGION}"
echo "Listing objects in bucket: $BUCKET_NAME"

OBJECTS=$(aws s3api list-objects-v2 \
  --bucket "$BUCKET_NAME" \
  --query "Contents[].Key" \
  --output text)

if [ -z "$OBJECTS" ] || [ "$OBJECTS" == "None" ]; then
  echo "Bucket is already empty"
else
  for KEY in $OBJECTS; do
    echo "Deleting: $KEY"
    aws s3api delete-object \
      --bucket "$BUCKET_NAME" \
      --key "$KEY"
  done
fi

export AWS_CLI_AUTO_PROMPT=on

echo "Done!"
