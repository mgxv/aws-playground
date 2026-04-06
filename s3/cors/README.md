# S3 Static Website Hosting with CORS

Host a static website on S3 with public read access and cross-origin resource support.

## Prerequisites

- [AWS CLI](https://aws.amazon.com/cli/) installed and configured (`aws configure`)
- [`jq`](https://stedolan.github.io/jq/) installed for JSON formatting
- IAM permissions for S3 (`s3:CreateBucket`, `s3:PutBucketPolicy`, `s3:PutBucketWebsite`, etc.)

---

## Files

| File | Description |
|---|---|
| `index.html` | Static site with a CORS fetch demo |
| `website.json` | S3 website hosting configuration |
| `generate-policy.sh` | Generates a public read bucket policy |

---

## Setup

### 1. Create the Bucket
```sh
aws s3api create-bucket \
  --bucket "demo-$(aws sts get-caller-identity --query Account --output text)-$(aws configure get region)-an" \
  --create-bucket-configuration LocationConstraint=$(aws configure get region)
```

### 2. Disable Block Public Access

Allows the bucket policy to grant public read access.
```sh
aws s3api put-public-access-block \
  --bucket "demo-$(aws sts get-caller-identity --query Account --output text)-$(aws configure get region)-an" \
  --public-access-block-configuration \
    '{"BlockPublicAcls": true, "IgnorePublicAcls": true, "BlockPublicPolicy": false, "RestrictPublicBuckets": false}'
```

### 3. Generate and Apply Bucket Policy

Generate `policy.json`:
```sh
./generate-policy.sh demo
```

Apply it:
```sh
aws s3api put-bucket-policy \
  --bucket "demo-$(aws sts get-caller-identity --query Account --output text)-$(aws configure get region)-an" \
  --policy file://policy.json
```

Verify:
```sh
aws s3api get-bucket-policy \
  --bucket "demo-$(aws sts get-caller-identity --query Account --output text)-$(aws configure get region)-an" \
  --query Policy \
  --output text | jq .
```

### 4. Enable Static Website Hosting
```sh
aws s3api put-bucket-website \
  --bucket "demo-$(aws sts get-caller-identity --query Account --output text)-$(aws configure get region)-an" \
  --website-configuration file://website.json
```

`website.json`:
```json
{
  "IndexDocument": { "Suffix": "index.html" },
  "ErrorDocument": { "Key": "error.html" }
}
```

### 5. Upload Files
```sh
aws s3 cp index.html s3://demo-$(aws sts get-caller-identity --query Account --output text)-$(aws configure get region)-an
```

### 6. Open the Website

Print the endpoint URL and open it in your browser:
```sh
echo "http://demo-$(aws sts get-caller-identity --query Account --output text)-$(aws configure get region)-an.s3-website-$(aws configure get region).amazonaws.com"
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `404 Not Found` on bucket commands | Bucket doesn't exist or wrong region | Run `aws s3 ls` to confirm the bucket name |
| `403 Forbidden` on the website URL | Public access still blocked or policy missing | Re-check steps 2 and 3 |
| `NoSuchBucketPolicy` | Policy was never applied | Re-run step 3 |
| CORS fetch fails in browser | External API blocked or S3 CORS not configured | Check the browser console; add a CORS config to the bucket if fetching from S3 resources |
| Bucket name truncated | `aws configure get region` returned empty | Run `aws configure set region <your-region>` |
