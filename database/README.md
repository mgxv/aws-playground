# Deploying an Amazon Aurora (PostgreSQL-Compatible) Cluster on AWS

This guide walks through provisioning a complete AWS network stack (VPC, subnets across two Availability Zones, routing, security group) and launching an **Amazon Aurora PostgreSQL-Compatible** cluster with a writer instance using the AWS CLI.

---

## Prerequisites

- [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) installed and configured (`aws configure`)
- An AWS account with permissions to create VPC, RDS, and security group resources
- `curl` and a POSIX shell (bash/zsh)
- A PostgreSQL client (`psql`) for testing the connection

> **Cost note:** Aurora is **not free-tier eligible** in the same way EC2 is. The smallest instance class used here (`db.t3.medium`) costs roughly ~$0.073/hour plus storage (~$0.10/GB-month) and I/O charges. **Always run the cleanup step (Step 8) when you're done** to avoid ongoing charges. Consider [Aurora Serverless v2](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-serverless-v2.html) if your workload is intermittent.

> **Engine version freshness:** Aurora PostgreSQL engine versions are updated regularly. The version used in this guide is current as of writing; check `aws rds describe-db-engine-versions --engine aurora-postgresql` for the latest available.

Set your region once so you don't have to pass `--region` on every command:

```bash
export AWS_DEFAULT_REGION=us-east-2
```

Each `create-*` command in this guide returns an ID or identifier. Save it from the command's output — later steps reference these as `$VPC_ID`, `$IGW_ID`, `$SUBNET_A_ID`, `$SUBNET_B_ID`, `$RTB_ID`, `$SG_ID`, `$SUBNET_GROUP_NAME`, and `$CLUSTER_ID`.

---

## Step 1: Create the VPC

A **Virtual Private Cloud (VPC)** is your own isolated network inside AWS. Every Aurora cluster must live inside a VPC. We define its private IP range with a CIDR block.

```bash
aws ec2 create-vpc \
  --cidr-block 10.0.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=demo-db-vpc}]' \
  --query 'Vpc.VpcId' --output text
```

**What this does:**
- `--cidr-block 10.0.0.0/16` reserves the private IP range `10.0.0.0` – `10.0.255.255` (65,536 addresses) for this VPC.
- `--tag-specifications` attaches a `Name` tag (`demo-db-vpc`) so the VPC is identifiable in the AWS Console.
- `--query 'Vpc.VpcId' --output text` extracts just the VPC ID from the JSON response. Save this ID — you'll reference it in later commands as `$VPC_ID`.

```bash
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-support
```

**Why:** Aurora requires both DNS hostnames and DNS support enabled on the VPC. The cluster endpoint is published as a DNS name that clients resolve to the current writer instance, so DNS resolution inside the VPC must work.

---

## Step 2: Create Two Subnets in Different Availability Zones

Aurora requires a **DB subnet group** that spans **at least two Availability Zones**, even if you only launch a single instance. This is non-negotiable: it allows Aurora to fail over to another AZ if the primary AZ has an outage.

```bash
aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.1.0/24 \
  --availability-zone us-east-2a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=demo-db-subnet-a}]' \
  --query 'Subnet.SubnetId' --output text
```

```bash
aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.2.0/24 \
  --availability-zone us-east-2b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=demo-db-subnet-b}]' \
  --query 'Subnet.SubnetId' --output text
```

**What this does:**
- Carves out two `/24` ranges (256 addresses each) from the VPC range, one in `us-east-2a` (save as `$SUBNET_A_ID`) and one in `us-east-2b` (save as `$SUBNET_B_ID`).
- These will be combined into a DB subnet group in Step 5.

> **Note:** Database instances should never have public IPs in production. We will, however, set `PubliclyAccessible=true` on the cluster in Step 6 so you can connect from your laptop for testing — this is a *demo convenience* and should be removed for any real workload.

---

## Step 3: Create an Internet Gateway and Route Table

For this demo, we want to be able to connect to the database from your local machine, so the subnets need a route to an internet gateway. **In a production setup you would skip this entirely** and instead connect via a bastion host, VPN, or AWS Client VPN.

```bash
aws ec2 create-internet-gateway \
  --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=demo-db-igw}]' \
  --query 'InternetGateway.InternetGatewayId' --output text

aws ec2 attach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID
```

Save the returned ID as `$IGW_ID`.

```bash
aws ec2 create-route-table \
  --vpc-id $VPC_ID \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=demo-db-rtb}]' \
  --query 'RouteTable.RouteTableId' --output text

aws ec2 create-route \
  --route-table-id $RTB_ID \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id $IGW_ID

aws ec2 associate-route-table --route-table-id $RTB_ID --subnet-id $SUBNET_A_ID
aws ec2 associate-route-table --route-table-id $RTB_ID --subnet-id $SUBNET_B_ID
```

**What this does:**
1. Creates and attaches an internet gateway to the VPC.
2. Creates a route table with a default route (`0.0.0.0/0`) pointing at the IGW.
3. Associates the route table with **both** subnets so either AZ can reach the internet.

---

## Step 4: Create a Security Group

A **security group** is a stateful virtual firewall. By default all inbound traffic is denied, so we need to explicitly allow PostgreSQL (TCP/5432).

```bash
aws ec2 create-security-group \
  --group-name demo-db-sg \
  --description "Allow PostgreSQL access for Aurora demo" \
  --vpc-id $VPC_ID \
  --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=demo-db-sg}]' \
  --query 'GroupId' --output text
```

Save the returned ID as `$SG_ID`.

**Allow PostgreSQL only from your current IP** (never open 5432 to the world). First, look up your public IP:

```bash
curl -s https://checkip.amazonaws.com
```

Then authorize it (replace `YOUR.IP.ADDR.ESS` with the value from above):

```bash
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp --port 5432 --cidr YOUR.IP.ADDR.ESS/32
```

**Why the `/32` on your IP:** A `/32` CIDR matches exactly one IP address. Opening a database port to `0.0.0.0/0` is one of the most common — and most damaging — cloud misconfigurations; databases get scanned and brute-forced within minutes of being exposed.

> **Heads-up:** If your home ISP gives you a dynamic IP, you'll need to re-run the authorize command whenever your IP changes. For real workloads, the security group should only allow traffic from application security groups within the VPC, not from the public internet at all.

---

## Step 5: Create a DB Subnet Group

A **DB subnet group** is the RDS-specific resource that tells Aurora which subnets it may place instances into. It must reference at least two subnets in different AZs.

```bash
aws rds create-db-subnet-group \
  --db-subnet-group-name demo-db-subnet-group \
  --db-subnet-group-description "Subnet group for Aurora PostgreSQL demo" \
  --subnet-ids $SUBNET_A_ID $SUBNET_B_ID \
  --tags 'Key=Name,Value=demo-db-subnet-group'
```

Save the name as `$SUBNET_GROUP_NAME=demo-db-subnet-group`. Unlike VPC resources, RDS resources are referenced by name rather than by an opaque ID.

---

## Step 6: Create the Aurora Cluster and Writer Instance

An Aurora deployment has two parts:
1. **The cluster** — the logical container that holds your data, manages storage (which is decoupled from compute), and exposes endpoints.
2. **One or more DB instances** — the actual compute nodes that process queries.

You must create them in that order.

**Generate and store a strong master password.** Do not paste a password into your shell history; use a generated value and store it in a secrets manager for real workloads.

```bash
export DB_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)
echo "Master password: $DB_PASSWORD"   # save this somewhere safe
```

**Create the cluster:**

```bash
aws rds create-db-cluster \
  --db-cluster-identifier demo-aurora-cluster \
  --engine aurora-postgresql \
  --engine-version 16.4 \
  --master-username dbadmin \
  --master-user-password "$DB_PASSWORD" \
  --db-subnet-group-name demo-db-subnet-group \
  --vpc-security-group-ids $SG_ID \
  --database-name appdb \
  --backup-retention-period 1 \
  --storage-encrypted \
  --tags 'Key=Name,Value=demo-aurora-cluster'
```

**What each flag does:**
- `--db-cluster-identifier demo-aurora-cluster` — The cluster's name. Save as `$CLUSTER_ID`.
- `--engine aurora-postgresql` — Selects the PostgreSQL-compatible Aurora engine (as opposed to `aurora-mysql`).
- `--engine-version 16.4` — Pins to a specific PostgreSQL major/minor version. Run `aws rds describe-db-engine-versions --engine aurora-postgresql --query 'DBEngineVersions[*].EngineVersion'` to see what's currently offered.
- `--master-username dbadmin` — Superuser-equivalent account created on first boot. Avoid `postgres` and `admin` as they are commonly targeted.
- `--master-user-password` — The password generated above. Quote it to avoid shell expansion of special characters.
- `--db-subnet-group-name` — Tells Aurora which subnets it may use.
- `--vpc-security-group-ids $SG_ID` — Attaches the firewall.
- `--database-name appdb` — Creates an initial database named `appdb` inside the cluster. Without this, you'd connect to the default `postgres` database and have to `CREATE DATABASE` yourself.
- `--backup-retention-period 1` — Keeps automated backups for 1 day. Minimum is 1; production should be 7+.
- `--storage-encrypted` — Enables encryption at rest using the default AWS-managed KMS key. **There is no good reason to leave this off.**

**Create the writer instance:**

The cluster on its own has no compute — you must attach at least one DB instance to it.

```bash
aws rds create-db-instance \
  --db-instance-identifier demo-aurora-writer \
  --db-cluster-identifier demo-aurora-cluster \
  --engine aurora-postgresql \
  --db-instance-class db.t3.medium \
  --publicly-accessible \
  --tags 'Key=Name,Value=demo-aurora-writer'
```

**What each flag does:**
- `--db-instance-identifier demo-aurora-writer` — The instance's name.
- `--db-cluster-identifier` — Attaches this instance to the cluster created above. The instance inherits the cluster's subnet group, security groups, engine, and credentials.
- `--db-instance-class db.t3.medium` — The smallest instance class supported by Aurora PostgreSQL (2 vCPU, 4 GB RAM). Burstable, suitable only for dev/test.
- `--publicly-accessible` — **Demo only.** Assigns a public DNS name so you can connect from outside the VPC. Combined with the security group restricting access to your IP, this is acceptable for a demo but should never be used in production.

**Wait for the cluster and instance to become available:**

```bash
aws rds wait db-instance-available --db-instance-identifier demo-aurora-writer
```

This typically takes **5–10 minutes** for Aurora — significantly longer than launching an EC2 instance.

**Retrieve the cluster endpoint:**

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier demo-aurora-cluster \
  --query 'DBClusters[0].Endpoint' --output text
```

The **cluster endpoint** always points to the current writer. If you later add reader instances, use the separate **reader endpoint** for read-only queries to load-balance across them.

---

## Step 7: Verify and Connect

Connect using `psql` (replace `$CLUSTER_ENDPOINT` with the address from above):

```bash
psql "host=$CLUSTER_ENDPOINT port=5432 dbname=appdb user=dbadmin sslmode=require"
```

You'll be prompted for the password you generated in Step 6. Once connected, verify:

```sql
SELECT version();
SELECT current_database(), current_user;
\l
```

> **Always use `sslmode=require`** (or stricter). Aurora supports TLS out of the box and there's no reason to send credentials or query data over a plaintext connection. For stricter verification, download the [Amazon RDS root certificate bundle](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.SSL.html) and use `sslmode=verify-full`.

**If the connection hangs or is refused:**
- Confirm your current public IP still matches the security group rule (`curl -s https://checkip.amazonaws.com`).
- Check that the cluster status is `available`: `aws rds describe-db-clusters --db-cluster-identifier demo-aurora-cluster --query 'DBClusters[0].Status'`.
- Verify the instance is `available` and `PubliclyAccessible` is `true`.
- Check CloudWatch Logs for the cluster if errors occur during connection.

---

## Step 8: Cleanup

Aurora is meaningfully expensive to leave running, so tear everything down promptly. Resources must be deleted in **reverse order of creation**.

```bash
# 1. Delete the writer instance and wait
aws rds delete-db-instance \
  --db-instance-identifier demo-aurora-writer \
  --skip-final-snapshot
aws rds wait db-instance-deleted --db-instance-identifier demo-aurora-writer

# 2. Delete the cluster (skipping the final snapshot to avoid storage charges)
aws rds delete-db-cluster \
  --db-cluster-identifier demo-aurora-cluster \
  --skip-final-snapshot
aws rds wait db-cluster-deleted --db-cluster-identifier demo-aurora-cluster

# 3. Delete the DB subnet group
aws rds delete-db-subnet-group --db-subnet-group-name demo-db-subnet-group

# 4. Delete the security group
aws ec2 delete-security-group --group-id $SG_ID

# 5. Disassociate and delete the route table
aws ec2 describe-route-tables \
  --route-table-ids $RTB_ID \
  --query 'RouteTables[0].Associations[*].RouteTableAssociationId' --output text
# For each association ID returned:
aws ec2 disassociate-route-table --association-id $RTB_ASSOC
aws ec2 delete-route-table --route-table-id $RTB_ID

# 6. Detach and delete the internet gateway
aws ec2 detach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID
aws ec2 delete-internet-gateway --internet-gateway-id $IGW_ID

# 7. Delete both subnets
aws ec2 delete-subnet --subnet-id $SUBNET_A_ID
aws ec2 delete-subnet --subnet-id $SUBNET_B_ID

# 8. Delete the VPC
aws ec2 delete-vpc --vpc-id $VPC_ID
```

> **About `--skip-final-snapshot`:** This is appropriate for throwaway demos. For any cluster holding real data, **omit this flag** and provide `--final-db-snapshot-identifier` so you have a recovery point. Be aware that retained snapshots continue to incur storage charges until you delete them.

**Why this order matters:**
- The cluster can't be deleted while it has instances attached.
- The subnet group can't be deleted while a cluster references it.
- The security group can't be deleted while a database is using it.
- The route table, IGW, subnets, and VPC follow the same dependency rules as in the Nginx guide.

> **Verify cleanup:** Check the RDS and VPC dashboards in the AWS Console to confirm nothing was missed. Also check the **Snapshots** tab in RDS — manual or automated snapshots can survive cluster deletion and quietly accumulate charges.

---

## Resource Name Reference

| Resource | Name / Identifier |
|---|---|
| VPC | `demo-db-vpc` |
| Internet Gateway | `demo-db-igw` |
| Subnet (AZ a) | `demo-db-subnet-a` |
| Subnet (AZ b) | `demo-db-subnet-b` |
| Route Table | `demo-db-rtb` |
| Security Group | `demo-db-sg` |
| DB Subnet Group | `demo-db-subnet-group` |
| Aurora Cluster | `demo-aurora-cluster` |
| Writer Instance | `demo-aurora-writer` |
| Initial Database | `appdb` |
| Master Username | `dbadmin` |

---

## Architecture Summary

```
Your Laptop
   │ (psql, TLS)
   ▼
Internet Gateway ──────┐
                       │
┌──────────────────────┼──────────────────────────────┐
│  VPC (10.0.0.0/16)   │                              │
│                      ▼                              │
│   ┌─────────────────────────────────────────────┐   │
│   │  Route Table:  0.0.0.0/0 → IGW              │   │
│   └─────────────────────────────────────────────┘   │
│           │                          │              │
│   ┌───────▼────────────┐   ┌─────────▼───────────┐  │
│   │ Subnet A           │   │ Subnet B            │  │
│   │ 10.0.1.0/24        │   │ 10.0.2.0/24         │  │
│   │ us-east-2a         │   │ us-east-2b          │  │
│   │                    │   │                     │  │
│   │ ┌────────────────┐ │   │ (failover capacity) │  │
│   │ │ Aurora Writer  │ │   │                     │  │
│   │ │ db.t3.medium   │ │   │                     │  │
│   │ │ PostgreSQL 16  │ │   │                     │  │
│   │ └────────────────┘ │   │                     │  │
│   └────────────────────┘   └─────────────────────┘  │
│                                                     │
│        ┌──────────────────────────────────┐         │
│        │ Aurora Storage (cluster volume)  │         │
│        │ 6-way replicated across 3 AZs    │         │
│        │ Encrypted at rest                │         │
│        └──────────────────────────────────┘         │
└─────────────────────────────────────────────────────┘
```

---

## Troubleshooting

| Problem | Likely Cause | Fix |
|---|---|---|
| `psql` hangs or times out | Security group missing 5432 rule, or your IP changed | Re-check `curl -s https://checkip.amazonaws.com` and re-authorize |
| `psql: FATAL: password authentication failed` | Wrong password, or shell mangled special characters | Reset via `aws rds modify-db-cluster --master-user-password ...` |
| `DBSubnetGroupDoesNotCoverEnoughAZs` | Subnet group has subnets in only one AZ | Add a second subnet in a different AZ before creating the cluster |
| Cluster stuck in `creating` for >15 minutes | Capacity issue in the chosen AZ, or invalid engine version | Check the RDS Events console; try a different `--engine-version` |
| `InvalidParameterCombination: publicly accessible ... not in a publicly accessible subnet` | Subnets have no route to an IGW | Confirm Step 3 ran and the route table is associated with both subnets |
| `DependencyViolation` deleting VPC | Lingering ENIs from the cluster | Wait a few minutes after cluster deletion; ENIs are reaped asynchronously |
| Surprise charges after cleanup | Retained manual or automated snapshots | Delete them under RDS → Snapshots in the Console |
