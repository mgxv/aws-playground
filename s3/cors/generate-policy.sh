#!/usr/bin/env bash

if [ -z "$1" ]; then
    echo "Usage: $0 <bucket-name>"
    exit 1
fi

export AWS_CLI_AUTO_PROMPT=off

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=$(aws configure get region)
BUCKET_NAME="${1}-${ACCOUNT_ID}-${REGION}-an"

POLICY=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "PublicReadGetObject",
            "Effect": "Allow",
            "Principal": "*",
            "Action": [
                "s3:GetObject"
            ],
            "Resource": [
                "arn:aws:s3:::${BUCKET_NAME}/*"
            ]
        }
    ]
}
EOF
)

echo "$POLICY" > policy.json

export AWS_CLI_AUTO_PROMPT=on

echo "Done!"
