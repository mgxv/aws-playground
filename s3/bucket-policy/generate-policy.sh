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
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::${ACCOUNT_ID}:root"
            },
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::${BUCKET_NAME}",
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
