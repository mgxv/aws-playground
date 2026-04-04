# AWS VPC Setup Scripts

## Overview

This project contains two Bash scripts for creating and destroying a fully functional AWS VPC using the AWS CLI. The purpose of this activity is to practice provisioning core AWS networking infrastructure from the command line, without relying on the AWS Console or infrastructure-as-code tools like Terraform.

---

## Scripts

| Script | Purpose |
|---|---|
| `create-vpc.sh` | Provisions all VPC resources from scratch |
| `delete-vpc.sh` | Tears down all resources created by `create-vpc.sh` |

---

## Architecture

The following resources are created by `create-vpc.sh`:

```
┌─────────────────────────────────────────┐
│  VPC (172.1.0.0/16)                     │
│                                         │
│  ┌──────────────────────────────────┐   │
│  │  Public Subnet (172.1.1.0/24)    │   │
│  │  - Auto-assign public IP: ON     │   │
│  └──────────────┬───────────────────┘   │
│                 │                       │
│  ┌──────────────▼───────────────────┐   │
│  │  Route Table                     │   │
│  │  - 0.0.0.0/0 → Internet Gateway  │   │
│  └──────────────┬───────────────────┘   │
│                 │                       │
└─────────────────┼───────────────────────┘
                  │
     ┌────────────▼────────────┐
     │   Internet Gateway      │
     │   (MyIGW)               │
     └─────────────────────────┘
                  │
              Internet
```

### Resources Created

| Resource | Name | CIDR / Details |
|---|---|---|
| VPC | `MyVPC` | `172.1.0.0/16` — 65,536 IPs |
| Internet Gateway | `MyIGW` | Attached to `MyVPC` |
| Public Subnet | `MyPublicSubnet` | `172.1.1.0/24` — 251 usable IPs |
| Route Table | *(main, auto-created)* | Default route `0.0.0.0/0 → MyIGW` |

---

## Requirements

- AWS CLI installed and configured (`aws configure`)
- IAM permissions:

**create-vpc.sh:**
```
ec2:CreateVpc
ec2:ModifyVpcAttribute
ec2:CreateInternetGateway
ec2:AttachInternetGateway
ec2:CreateSubnet
ec2:ModifySubnetAttribute
ec2:DescribeRouteTables
ec2:AssociateRouteTable
ec2:CreateRoute
```

**delete-vpc.sh:**
```
ec2:DescribeVpcs
ec2:DescribeInternetGateways
ec2:DescribeSubnets
ec2:DescribeRouteTables
ec2:DeleteRoute
ec2:DisassociateRouteTable
ec2:DeleteSubnet
ec2:DetachInternetGateway
ec2:DeleteInternetGateway
ec2:DeleteVpc
```

---

## Usage

### 1. Make the scripts executable

```bash
chmod u+x create-vpc.sh delete-vpc.sh
```

### 2. Create the VPC

```bash
./create-vpc.sh
```

Expected output:
```
Account ID:          123456789012
Region:              us-east-1
Creating VPC...
VPC ID:              vpc-0xxxxxxxxxxxxxxxxx
Enabling DNS hostnames on VPC...
Enabling DNS support on VPC...
Creating Internet Gateway...
IGW ID:              igw-0xxxxxxxxxxxxxxxxx
Attaching IGW to VPC...
Creating public subnet...
Subnet ID:           subnet-0xxxxxxxxxxxxxxxxx
Enabling auto-assign public IP on subnet...
Route Table ID:      rtb-0xxxxxxxxxxxxxxxxx
Associating subnet with route table...
Adding internet route to route table...

=============================
VPC setup complete!
=============================
Account ID:          123456789012
Region:              us-east-1
VPC ID:              vpc-0xxxxxxxxxxxxxxxxx
IGW ID:              igw-0xxxxxxxxxxxxxxxxx
Subnet ID:           subnet-0xxxxxxxxxxxxxxxxx
Route Table ID:      rtb-0xxxxxxxxxxxxxxxxx
=============================
```

### 3. Delete the VPC

```bash
./delete-vpc.sh
```

Expected output:
```
=============================
VPC cleanup complete!
=============================
Account ID:          123456789012
Region:              us-east-1
VPC ID:              vpc-0xxxxxxxxxxxxxxxxx  ✓ deleted
IGW ID:              igw-0xxxxxxxxxxxxxxxxx  ✓ deleted
Subnet ID:           subnet-0xxxxxxxxxxxxxxxxx  ✓ deleted
Route Table ID:      rtb-0xxxxxxxxxxxxxxxxx  ✓ deleted (with VPC)
=============================
```

---

## Deletion Order

AWS enforces dependency constraints between resources — they must be deleted in the reverse order they were created:

```
1. Delete Route        (0.0.0.0/0 → IGW)
2. Disassociate Subnet from Route Table
3. Delete Subnet
4. Detach Internet Gateway from VPC
5. Delete Internet Gateway
6. Delete VPC          (also removes the default Route Table and Security Group)
```

---

## Notes

- **DNS support and DNS hostnames** are both enabled on the VPC so that EC2 instances receive public DNS hostnames automatically.
- **Auto-assign public IP** is enabled on the subnet so instances launched into it are reachable from the internet without needing a manually assigned Elastic IP.
- The **Route Table** used is the default main route table automatically created by AWS with the VPC. No additional route table is created.
- `set -e` is used in both scripts so they exit immediately if any command fails, preventing partial resource states.
- Both scripts suppress raw JSON output from the AWS CLI using `--query` and `--output text > /dev/null` for clean, readable logs.