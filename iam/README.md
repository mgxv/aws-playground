# AWS IAM: Create User, Attach ReadOnly Policy, and Create a Custom Policy

This guide walks through creating an IAM user with the AWS CLI, attaching the AWS-managed `ReadOnlyAccess` policy, and creating a custom policy.

## Prerequisites

- AWS CLI v2 installed (`aws --version`)
- Configured credentials with IAM permissions (`aws configure`)
- An admin or IAM-privileged identity to run these commands

---

## Step 1 — Create the IAM user

```bash
aws iam create-user --user-name demo-readonly-user
```

Verify it exists:

```bash
aws iam get-user --user-name demo-readonly-user
```

---

## Step 2 — Attach the AWS-managed ReadOnlyAccess policy

AWS provides a built-in policy named `ReadOnlyAccess` that grants read-only permissions across most services.

```bash
aws iam attach-user-policy \
  --user-name demo-readonly-user \
  --policy-arn arn:aws:iam::aws:policy/ReadOnlyAccess
```

Confirm the attachment:

```bash
aws iam list-attached-user-policies --user-name demo-readonly-user
```

---

## Step 3 — (Optional) Create access keys for programmatic access

```bash
aws iam create-access-key --user-name demo-readonly-user
```

Save the `AccessKeyId` and `SecretAccessKey` from the output — the secret is shown only once.

---

## Step 4 — Create a custom IAM policy

IAM policies must be submitted to AWS as **JSON**. Create a file named `policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowS3ReadAll",
      "Effect": "Allow",
      "Action": [
        "s3:Get*",
        "s3:List*",
        "s3:Describe*"
      ],
      "Resource": [
        "arn:aws:s3:::my-demo-bucket",
        "arn:aws:s3:::my-demo-bucket/*"
      ]
    }
  ]
}
```

This grants every S3 read-level action on `my-demo-bucket`, including downloading objects (`s3:GetObject`), listing bucket contents, and reading bucket/object metadata.

Create the policy in IAM:

```bash
aws iam create-policy \
  --policy-name DemoS3ReadPolicy \
  --policy-document file://policy.json
```

The output includes the policy ARN — note it for the next step. It will look like:

```
arn:aws:iam::<account-id>:policy/DemoS3ReadPolicy
```

---

## Step 5 — Attach the custom policy to the user

Look up the policy ARN:

```bash
aws iam list-policies --scope Local \
  --query "Policies[?PolicyName=='DemoS3ReadPolicy'].Arn" \
  --output text
```

Then attach it:

```bash
aws iam attach-user-policy \
  --user-name demo-readonly-user \
  --policy-arn <arn>
```

Verify both policies are now attached:

```bash
aws iam list-attached-user-policies --user-name demo-readonly-user
```

---

## Cleanup

Run these steps in order to fully remove everything created above. IAM requires a user to have no attached policies, access keys, login profile, or group memberships before it can be deleted.

### 1. Detach the managed and custom policies

```bash
aws iam detach-user-policy \
  --user-name demo-readonly-user \
  --policy-arn arn:aws:iam::aws:policy/ReadOnlyAccess

aws iam detach-user-policy \
  --user-name demo-readonly-user \
  --policy-arn <arn>
```

### 2. Delete any access keys

List the keys to get their IDs:

```bash
aws iam list-access-keys --user-name demo-readonly-user
```

Then delete each one:

```bash
aws iam delete-access-key \
  --user-name demo-readonly-user \
  --access-key-id AKIAEXAMPLE12345
```

### 3. Delete the custom policy

Look up the ARN again if needed:

```bash
aws iam list-policies --scope Local \
  --query "Policies[?PolicyName=='DemoS3ReadPolicy'].Arn" \
  --output text
```

If the policy has multiple non-default versions (e.g. you ran `create-policy-version` to update it), list and delete those first:

```bash
aws iam list-policy-versions --policy-arn <arn>
```

Then delete the policy itself:

```bash
aws iam delete-policy --policy-arn <arn>
```

### 4. Delete the IAM user

```bash
aws iam delete-user --user-name demo-readonly-user
```

### 5. Verify everything is gone

```bash
aws iam get-user --user-name demo-readonly-user
```

This should return a `NoSuchEntity` error, confirming the user no longer exists.
