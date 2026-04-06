# STS Role Assumption Demo

This exercise demonstrates how to use AWS Security Token Service (STS) to assume an IAM role and gain temporary, scoped access to an S3 bucket. Rather than granting a user direct S3 permissions, the user assumes a role that has S3 permissions and receives short-lived temporary credentials.

## Architecture
```
sts-machine-user
    └── assumes → StsRole
                    └── access → sts-demo-<account-id>-<region> (S3 bucket)
```

## Create a user with no permissions

Create a new user with no permissions and generate access keys.
```sh
aws iam create-user --user-name sts-machine-user
```
```sh
aws iam create-access-key --user-name sts-machine-user --output table
```

## Configure the new user profile

Configure a named profile for the new user using the access keys generated above.
```sh
aws configure --profile sts-machine-user
```

Verify the credentials are set correctly:
```sh
aws sts get-caller-identity --profile sts-machine-user
```

Verify no access is permitted:
```sh
aws s3 ls --profile sts-machine-user
```

Expected result:
```
An error occurred (AccessDenied) when calling the ListBuckets operation: User: arn:aws:iam::<account-id>:user/sts-machine-user is not authorized to perform: s3:ListAllMyBuckets because no identity-based policy allows the s3:ListAllMyBuckets action
```

## Attach deploy permissions

Before deploying, attach the required inline policy to the user. This must be done using an admin account, not the `sts-machine-user` profile.
```sh
aws iam put-user-policy \
  --user-name sts-machine-user \
  --policy-name sts-deploy-policy \
  --policy-document file://policy.json \
  --profile default
```

The `policy.json` file grants the necessary CloudFormation, IAM, and S3 permissions for deployment. See `policy.json` in this directory.

## Deploy the CloudFormation stack

The stack creates two resources:
- An S3 bucket named `sts-demo-<account-id>-<region>`
- An IAM role that trusts `sts-machine-user` and grants `s3:*` access to the bucket
```sh
aws cloudformation deploy \
  --template-file template.yaml \
  --stack-name sts-stack \
  --capabilities CAPABILITY_IAM \
  --region us-east-2 \
  --profile sts-machine-user
```

Expected result:
```
Waiting for changeset to be created..
Waiting for stack create/update to complete
Successfully created/updated stack - sts-stack
```

## Assume the role

Use the role ARN from the previous step to assume the role and receive temporary credentials:
```sh
aws sts assume-role \
  --role-arn <role-arn> \
  --role-session-name sts-demo-session \
  --profile sts-machine-user
```

This returns temporary credentials:
```json
{
    "Credentials": {
        "AccessKeyId": "...",
        "SecretAccessKey": "...",
        "SessionToken": "...",
        "Expiration": "2026-04-03T21:00:00Z"
    }
}
```

Configure a new profile using the temporary credentials:
```sh
aws configure --profile assumed
aws configure set aws_session_token <SessionToken> --profile assumed
```

## Verify access

Verify you can now list and access the S3 bucket using the assumed role:
```sh
aws s3 ls --profile assumed
```

## Cleanup

Delete the CloudFormation stack to remove the S3 bucket and IAM role:
```sh
aws cloudformation delete-stack \
  --stack-name sts-stack \
  --region us-east-2 \
  --profile sts-machine-user

aws cloudformation wait stack-delete-complete \
  --stack-name sts-stack \
  --region us-east-2 \
  --profile sts-machine-user
```

Delete the inline policy and the user using the default (admin) profile:
```sh
aws iam delete-user-policy \
  --user-name sts-machine-user \
  --policy-name sts-deploy-policy \
  --profile default
```
```sh
aws iam delete-access-key \
  --user-name sts-machine-user \
  --access-key-id <access-key-id> \
  --profile default
```
```sh
aws iam delete-user \
  --user-name sts-machine-user \
  --profile default
```

> ⚠️ IAM users cannot be deleted while they still have access keys or policies attached. The steps above delete them in the correct order.

---

## Summary

This exercise walked through a core AWS security pattern — **role assumption via STS** — from scratch. Here's what was covered:

### Key concepts learned

**IAM Users vs Roles**
- A user (`sts-machine-user`) has long-lived credentials but starts with no permissions
- A role (`StsRole`) has no credentials of its own — it is assumed by a trusted identity to gain temporary access

**Trust policies**
- A role's trust policy controls *who* can assume it
- We updated the trust policy to explicitly allow `sts-machine-user` to assume `StsRole`
- Without this, `sts:AssumeRole` is denied even if the user has the permission

**Principle of least privilege**
- `sts-machine-user` has no direct S3 access — it can only reach S3 by assuming the role
- The role's S3 access is scoped to a single bucket (`sts-demo-*`)
- The deploy policy is scoped to `sts-stack-*` roles and `sts-demo-*` buckets only

**CloudFormation stacks**
- A stack groups related resources (`MyBucket` and `StsRole`) into a single deployable unit
- `--capabilities CAPABILITY_IAM` is required as an explicit acknowledgement that the template creates IAM resources
- Failed stacks roll back automatically, and a `ROLLBACK_FAILED` state requires a force delete before redeploying

**Resource-level vs account-level S3 actions**
- Actions like `s3:ListAllMyBuckets` operate at the account level and require `Resource: "*"`
- Actions like `s3:GetObject` operate at the bucket/object level and can be scoped to a specific ARN

**Temporary credentials**
- `sts:AssumeRole` returns an `AccessKeyId`, `SecretAccessKey`, and `SessionToken` that expire after 1 hour by default
- These are safer than long-lived credentials because they are short-lived and traceable to the session name
