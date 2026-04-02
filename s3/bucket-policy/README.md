# S3 Bucket Setup

Scripts to create an S3 bucket and apply a bucket policy with a dynamically generated name in the format: `<name>-<account-id>-<region>-an`.

---

## 1. Generate the Bucket Policy

Run the script with your desired bucket name prefix to generate `policy.json`:
```sh
chmod +x generate-policy.sh
./generate-policy.sh <bucket-name>
```

**Example:**
```sh
./generate-policy.sh demo
# Creates policy for: demo-123456789012-us-east-1-an
```

---

## 2. Create the Bucket
```sh
aws s3api create-bucket \
  --bucket "demo-$(aws sts get-caller-identity --query Account --output text)-$(aws configure get region)-an" \
  --bucket-namespace account-regional
```

---

## 3. Apply the Bucket Policy
```sh
aws s3api put-bucket-policy \
  --bucket "demo-$(aws sts get-caller-identity --query Account --output text)-$(aws configure get region)-an" \
  --policy file://policy.json
```

---

## 4. Get the Bucket Policy
```sh
aws s3api get-bucket-policy \
  --bucket "demo-$(aws sts get-caller-identity --query Account --output text)-$(aws configure get region)-an" \
  --query Policy \
  --output text | jq .
```

---

## 5. Delete the Bucket Policy
```sh
aws s3api delete-bucket-policy \
  --bucket "demo-$(aws sts get-caller-identity --query Account --output text)-$(aws configure get region)-an"
```

Verify the policy was removed:
```sh
aws s3api get-bucket-policy \
  --bucket "demo-$(aws sts get-caller-identity --query Account --output text)-$(aws configure get region)-an"
# Expected: NoSuchBucketPolicy error confirming deletion
```

---

## Bucket Naming Convention

| Part | Example | Description |
|---|---|---|
| `<name>` | `demo` | Your chosen prefix |
| `<account-id>` | `123456789012` | AWS account ID |
| `<region>` | `us-east-1` | Configured AWS region |
| `-an` | `-an` | Fixed suffix |

**Full example:** `demo-123456789012-us-east-1-an`
