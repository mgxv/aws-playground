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

read -p "Are you sure you want to nuke $BUCKET_NAME? (y/n): " CONFIRM
CONFIRM=$(echo "$CONFIRM" | tr '[:upper:]' '[:lower:]')
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "yes" ]; then
  echo "Aborted"
  exit 1
fi

echo "Emptying bucket: $BUCKET_NAME"
aws s3 rm s3://"$BUCKET_NAME" --recursive
echo "Bucket emptied"

echo "Deleting bucket: $BUCKET_NAME"
aws s3api delete-bucket --bucket "$BUCKET_NAME"
echo "Bucket deleted"

export AWS_CLI_AUTO_PROMPT=on

echo "Done!"
