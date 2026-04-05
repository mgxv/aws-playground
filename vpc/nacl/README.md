# AWS EC2 with Apache — Network ACL Lab

Deploy an EC2 instance running Apache inside a custom VPC, then explore how Network ACL rules can block and restore access at the subnet level.

---

## What You'll Build

- A VPC with an internet gateway, public subnet, and route table
- An EC2 instance (t3.micro) running Apache, deployed via CloudFormation
- An IAM role with SSM Session Manager access (no SSH keys needed)
- Network ACL rules to block and unblock your own IP address

---

## Prerequisites

- AWS CLI installed and configured (`aws configure`)
- IAM permissions for EC2, CloudFormation, and IAM (see individual scripts for specifics)
- Bash shell (macOS/Linux or WSL on Windows)

---

## Files

| File | Purpose |
|---|---|
| `template.yaml` | CloudFormation template — EC2 instance, security group, IAM role |
| `create-vpc.sh` | Creates the VPC, IGW, subnet, and route table |
| `create-stack.sh` | Deploys the CloudFormation stack |
| `create-rule.sh` | Adds a DENY rule to the NACL for your current IP |
| `delete-rule.sh` | Removes the DENY rule to restore access |
| `cleanup.sh` | Tears down all resources in the correct order |

---

## Step-by-Step

### 1 — Create the VPC

```bash
./create-vpc.sh
```

Creates:
- VPC `172.1.0.0/16` tagged `MyVPC`
- Internet Gateway `MyIGW`, attached to the VPC
- Public subnet `172.1.1.0/24` in `us-east-1a` tagged `MyPublicSubnet`
- Default route `0.0.0.0/0 → IGW` in the main route table

> **Note:** The subnet is pinned to `us-east-1a` because `t3.micro` is not available in `us-east-1e`.

---

### 2 — Deploy the EC2 Instance

```bash
./create-stack.sh
```

This script looks up the VPC and subnet by name tag, then deploys `template.yaml` as a CloudFormation stack (`MyEC2Stack`). It waits for the stack to complete and prints the instance's public IPv4 address.

Test that Apache is running:

```bash
curl http://<PUBLIC_IP>
```

You should see: `Hello from <hostname>`

---

### 3 — Block Your IP with a NACL Rule

```bash
./create-rule.sh
# Optional: specify a rule number (default: 90)
./create-rule.sh 100
```

This automatically looks up the `MyPublicSubnet` subnet, finds its associated NACL, fetches your current public IP, and inserts an inbound DENY rule for all protocols. Verify access is blocked:

```bash
curl http://<PUBLIC_IP>   # Should time out
```

---

### 4 — Restore Access

```bash
./delete-rule.sh
# Optional: specify rule number if you used a custom one
./delete-rule.sh 100
```

Removes the DENY rule and verifies it is gone. Access should be restored immediately.

---

### 5 — Clean Up

```bash
./cleanup.sh
```

Deletes all resources in the correct dependency order:

1. IAM role detached from instance profile
2. CloudFormation stack (EC2, security group, IAM role, instance profile)
3. Internet route from route table
4. Subnet disassociated from route table
5. Subnet deleted
6. IGW detached and deleted
7. VPC deleted

---

## Architecture

```
Internet
    │
    ▼
Internet Gateway (MyIGW)
    │
    ▼
VPC 172.1.0.0/16 (MyVPC)
    │
    ▼
Public Subnet 172.1.1.0/24 (MyPublicSubnet)  ←── Network ACL rules applied here
    │
    ▼
EC2 t3.micro (MyEC2Instance)
├── Apache serving on port 80
├── Security Group: allow all inbound/outbound
└── IAM Role: AmazonSSMManagedInstanceCore (SSM access)
```

---

## Key Concepts

**Network ACLs vs Security Groups**
NACLs operate at the subnet level and are stateless — you must explicitly allow return traffic. Security groups operate at the instance level and are stateful. This lab uses a NACL deny rule to block traffic before it even reaches the instance's security group.

**Rule evaluation order**
NACL rules are evaluated lowest-number-first. A DENY rule at number 90 is evaluated before the default ALLOW ALL at 32767, so the block takes effect even though the security group permits all traffic.

**Why rule 90?**
The default `create-rule.sh` uses rule number 90 to sit safely below the default rules (which typically start at 100) and well above the asterisk catch-all rule (32767). Pass a custom number as the second argument if needed.

**SSM Session Manager**
The EC2 instance has no key pair. Connect via the AWS Console → EC2 → Connect → Session Manager, or using the AWS CLI:

```bash
aws ssm start-session --target <INSTANCE_ID>
```

---

## Troubleshooting

| Issue | Likely Cause |
|---|---|
| `curl` times out after blocking | NACL rule is working correctly |
| `curl` still works after blocking | Your IP may have changed — re-run `create-rule.sh` |
| Stack creation fails | Ensure `create-vpc.sh` completed successfully first |
| Cleanup fails on VPC deletion | Check for lingering ENIs or security groups not managed by the stack |
