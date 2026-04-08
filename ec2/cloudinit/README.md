# Deploying an Nginx Web Server on AWS EC2 with Cloud-Init

This guide walks through provisioning a complete AWS network stack (VPC, subnet, routing, security group) and launching an EC2 instance that automatically installs and configures Nginx using a `cloud-init` user-data script.

---

## Prerequisites

- [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) installed and configured (`aws configure`)
- An AWS account with permissions to create VPC, EC2, and security group resources
- A `userdata.yaml` cloud-init file in your working directory
- `curl` and a POSIX shell (bash/zsh)

> **Cost note:** A `t3.micro` instance is free-tier eligible for new accounts. Outside the free tier, expect ~$0.01/hour plus negligible data transfer. **Always run the cleanup step (Step 8) when you're done** to avoid ongoing charges.

> **AMI freshness:** AMI IDs are region-specific and change over time as Amazon publishes patched images. The AMI used in this guide is current as of writing for **us-east-2**.

Set your region once so you don't have to pass `--region` on every command:

```bash
export AWS_DEFAULT_REGION=us-east-2
```

Each `create-*` command in this guide returns an ID. Save it from the command's output — later steps reference these IDs as `$VPC_ID`, `$IGW_ID`, `$SUBNET_ID`, `$RTB_ID`, `$SG_ID`, and `$INSTANCE_ID`.

---

## Step 1: Create the VPC

A **Virtual Private Cloud (VPC)** is your own isolated network inside AWS. Every EC2 instance must live inside a VPC. We define its private IP range with a CIDR block.

```bash
aws ec2 create-vpc \
  --cidr-block 10.0.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=demo-vpc}]' \
  --query 'Vpc.VpcId' --output text
```

**What this does:**
- `--cidr-block 10.0.0.0/16` reserves the private IP range `10.0.0.0` – `10.0.255.255` (65,536 addresses) for this VPC.
- `--tag-specifications` attaches a `Name` tag (`demo-vpc`) so the VPC is identifiable in the AWS Console.
- `--query 'Vpc.VpcId' --output text` extracts just the VPC ID from the JSON response. Save this ID — you'll reference it in later commands as `$VPC_ID`.

```bash
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames
```

**Why:** By default, instances in a new VPC get private DNS names but not public ones. Enabling DNS hostnames ensures your instance gets a public DNS name (e.g., `ec2-1-2-3-4.us-east-2.compute.amazonaws.com`) that resolves from the internet.

---

## Step 2: Create and Attach an Internet Gateway

An **Internet Gateway (IGW)** is the component that allows resources inside your VPC to communicate with the public internet. Without it, cloud-init can't download the Nginx package and you can't reach the web server from your browser.

```bash
aws ec2 create-internet-gateway \
  --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=demo-igw}]' \
  --query 'InternetGateway.InternetGatewayId' --output text
```

```bash
aws ec2 attach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID
```

**What this does:**
- Creates a standalone internet gateway tagged `demo-igw`. Save the returned ID as `$IGW_ID`.
- Attaches it to the VPC. An IGW only becomes functional once attached.

---

## Step 3: Create a Public Subnet

A **subnet** is a slice of the VPC's IP range, tied to a single Availability Zone. Instances are launched into subnets, not directly into the VPC.

```bash
aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.1.0/24 \
  --availability-zone us-east-2a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=demo-subnet}]' \
  --query 'Subnet.SubnetId' --output text
```

```bash
aws ec2 modify-subnet-attribute --subnet-id $SUBNET_ID --map-public-ip-on-launch
```

**What this does:**
- `--cidr-block 10.0.1.0/24` carves out 256 addresses (`10.0.1.0` – `10.0.1.255`) from the VPC range for this subnet.
- `--availability-zone us-east-2a` pins the subnet to one AZ. Change this if you're in a different region.
- `--map-public-ip-on-launch` tells AWS to automatically assign a public IP to any instance launched in this subnet. Without this flag, instances would only get private IPs and be unreachable from the internet.

> **Note:** A subnet only becomes "public" once it also has a route to an internet gateway (Step 4). The `map-public-ip-on-launch` attribute alone isn't enough.

---

## Step 4: Create a Route Table and Internet Route

A **route table** defines where network traffic from the subnet is directed. We need a route that sends all non-local traffic (`0.0.0.0/0`) to the internet gateway.

```bash
aws ec2 create-route-table \
  --vpc-id $VPC_ID \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=demo-rtb}]' \
  --query 'RouteTable.RouteTableId' --output text

aws ec2 create-route \
  --route-table-id $RTB_ID \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id $IGW_ID

aws ec2 associate-route-table --route-table-id $RTB_ID --subnet-id $SUBNET_ID
```

**What this does:**
1. Creates an empty route table in the VPC, tagged `demo-rtb`. (It automatically contains a `local` route for `10.0.0.0/16` traffic within the VPC.)
2. Adds a route: "anything destined for `0.0.0.0/0` (the internet) → send it to the IGW."
3. Associates the route table with our subnet, making the subnet truly public.

---

## Step 5: Create a Security Group

A **security group** is a stateful virtual firewall that controls inbound and outbound traffic to your instance. By default, all inbound traffic is denied, so we need to explicitly allow HTTP and SSH.

```bash
aws ec2 create-security-group \
  --group-name demo-sg \
  --description "Allow HTTP and SSH for nginx demo" \
  --vpc-id $VPC_ID \
  --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=demo-sg}]' \
  --query 'GroupId' --output text
```

**Allow HTTP from anywhere** so anyone on the internet can load the web page:

```bash
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp --port 80 --cidr 0.0.0.0/0
```

**Allow SSH only from your current IP** (safer than opening port 22 to the whole world). First, look up your public IP:

```bash
curl -s https://checkip.amazonaws.com
```

Then authorize it (replace `YOUR.IP.ADDR.ESS` with the value from above):

```bash
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp --port 22 --cidr YOUR.IP.ADDR.ESS/32
```

**Why the `/32` on your IP:** A `/32` CIDR matches exactly one IP address. This restricts SSH access so that only your current network can connect, dramatically reducing the attack surface compared to `0.0.0.0/0`.

> **Heads-up:** If your home ISP gives you a dynamic IP, you'll need to re-run the authorize command whenever your IP changes. For a long-lived environment, consider [AWS Systems Manager Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html) instead of opening port 22 at all.

---

## Step 6: Launch the EC2 Instance

Now we launch the instance into the subnet we prepared, attaching the security group and passing the cloud-init script as user data.

**Create a key pair** and save the private key locally with secure permissions:

```bash
aws ec2 create-key-pair \
  --key-name demo-key \
  --tag-specifications 'ResourceType=key-pair,Tags=[{Key=Name,Value=demo-key}]' \
  --query 'KeyMaterial' --output text > demo-key.pem
chmod 400 demo-key.pem
```

> **Security:** `chmod 400` is required — SSH refuses to use a private key file that is readable by other users on your system. Treat `demo-key.pem` like a password: never commit it to git, never share it, and delete it during cleanup.

**Launch the instance:**

```bash
aws ec2 run-instances \
  --image-id ami-051de6a4e7ae45f77 \
  --instance-type t3.micro \
  --key-name demo-key \
  --security-group-ids $SG_ID \
  --subnet-id $SUBNET_ID \
  --user-data file://userdata.yaml \
  --metadata-options 'HttpTokens=required,HttpEndpoint=enabled' \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=demo-instance}]' \
  --query 'Instances[0].InstanceId' --output text
```

**What each flag does:**
- `--image-id ami-051de6a4e7ae45f77` — Amazon Linux 2023 AMI in us-east-2. The OS image the instance boots from. (See the Prerequisites section for how to look up the latest ID.)
- `--instance-type t3.micro` — Small, cheap, free-tier-eligible instance type (2 vCPU, 1 GB RAM).
- `--key-name demo-key` — The SSH key pair to inject for `ec2-user` login.
- `--security-group-ids $SG_ID` — Attaches the firewall rules we created.
- `--subnet-id $SUBNET_ID` — Places the instance in our public subnet.
- `--user-data file://userdata.yaml` — Passes the cloud-init config to the instance. The `file://` prefix tells the AWS CLI to read the file's contents from your current working directory; it handles base64 encoding automatically. Cloud-init runs this script on first boot.
- `--metadata-options 'HttpTokens=required,HttpEndpoint=enabled'` — Forces **IMDSv2** (token-based instance metadata). This protects against SSRF attacks that could otherwise steal IAM role credentials from the instance metadata service. There is no good reason to use IMDSv1 on new instances.
- `--tag-specifications` — Tags the instance with `Name=demo-instance` so it's identifiable in the Console.

**Wait for the instance to reach the `running` state:**

```bash
aws ec2 wait instance-running --instance-ids $INSTANCE_ID
```

The `wait` subcommand polls until the condition is met, so the script doesn't race ahead before the instance is ready.

**Retrieve the public IP:**

```bash
aws ec2 describe-instances --instance-ids $INSTANCE_ID \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text
```

> **Important:** The instance reaches the `running` state before cloud-init finishes. Wait 1–2 minutes after launch for package installs and `runcmd` steps to complete before testing.

---

## Step 7: Verify and Debug

Once cloud-init has had time to finish, test it (replace `$PUBLIC_IP` with the address returned above):

```bash
curl http://$PUBLIC_IP
```

If you don't see your custom HTML page, SSH in and inspect the cloud-init logs:

```bash
ssh -i demo-key.pem ec2-user@$PUBLIC_IP
sudo cloud-init status --long
sudo tail -n 100 /var/log/cloud-init-output.log
```

**What to look for:**
- `cloud-init status --long` reports whether cloud-init finished successfully or errored.
- `/var/log/cloud-init-output.log` captures stdout/stderr from every package install and `runcmd` step — this is where you'll see failed package downloads, YAML syntax errors, or systemctl failures.
- `sudo systemctl status nginx` confirms whether the Nginx service itself is running.

---

## Step 8: Cleanup

AWS resources cost money (and leave clutter in your account), so tear everything down when you're done. Resources must be deleted in **reverse order of creation** because of dependencies — for example, you can't delete a VPC while it still contains a subnet.

```bash
# 1. Terminate the instance and wait for it to fully shut down
aws ec2 terminate-instances --instance-ids $INSTANCE_ID
aws ec2 wait instance-terminated --instance-ids $INSTANCE_ID

# 2. Delete the security group (must be after instance termination)
aws ec2 delete-security-group --group-id $SG_ID

# 3. Disassociate and delete the route table
aws ec2 describe-route-tables \
  --route-table-ids $RTB_ID \
  --query 'RouteTables[0].Associations[0].RouteTableAssociationId' --output text

aws ec2 disassociate-route-table --association-id $RTB_ASSOC
aws ec2 delete-route-table --route-table-id $RTB_ID

# 4. Detach and delete the internet gateway
aws ec2 detach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID
aws ec2 delete-internet-gateway --internet-gateway-id $IGW_ID

# 5. Delete the subnet
aws ec2 delete-subnet --subnet-id $SUBNET_ID

# 6. Delete the VPC
aws ec2 delete-vpc --vpc-id $VPC_ID

# 7. Delete the key pair (both in AWS and locally)
aws ec2 delete-key-pair --key-name demo-key
rm -f demo-key.pem
```

**Why this order matters:**
- The security group can't be deleted while an instance is using it.
- The route table can't be deleted while it's associated with a subnet.
- The IGW can't be deleted while it's attached to a VPC.
- The subnet can't be deleted while it contains an instance (already handled) or has a route table association.
- The VPC can't be deleted until it is empty of subnets, gateways, and security groups.

> **Verify cleanup:** After running the commands above, check the EC2 and VPC dashboards in the AWS Console to confirm nothing was missed. Lingering Elastic Network Interfaces (ENIs) are a common cause of `DependencyViolation` errors.

---

## Resource Name Reference

| Resource | Name tag |
|---|---|
| VPC | `demo-vpc` |
| Internet Gateway | `demo-igw` |
| Subnet | `demo-subnet` |
| Route Table | `demo-rtb` |
| Security Group | `demo-sg` |
| EC2 Instance | `demo-instance` |
| Key Pair | `demo-key` |

---

## Architecture Summary

```
Internet
   │
   ▼
Internet Gateway ──────┐
                       │
┌──────────────────────┼──────────────────────┐
│  VPC (10.0.0.0/16)   │                      │
│                      ▼                      │
│   ┌─────────────────────────────────────┐   │
│   │  Route Table                        │   │
│   │  0.0.0.0/0 → IGW                    │   │
│   │  10.0.0.0/16 → local                │   │
│   └─────────────────────────────────────┘   │
│                      │                      │
│   ┌──────────────────▼──────────────────┐   │
│   │  Subnet (10.0.1.0/24, us-east-2a)   │   │
│   │                                     │   │
│   │   ┌─────────────────────────────┐   │   │
│   │   │ EC2 Instance (t3.micro)     │   │   │
│   │   │  - Amazon Linux 2023        │   │   │
│   │   │  - Nginx (via cloud-init)   │   │   │
│   │   │  - IMDSv2 enforced          │   │   │
│   │   │  - SG: 80 ← any, 22 ← you   │   │   │
│   │   └─────────────────────────────┘   │   │
│   └─────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
```

---

## Troubleshooting

| Problem | Likely Cause | Fix |
|---|---|---|
| `curl` hangs or times out | Security group missing port 80 rule, or IGW/route table misconfigured | Verify `authorize-security-group-ingress` ran successfully; check route table has `0.0.0.0/0 → IGW` |
| SSH "connection refused" | Wrong username, key, or SG rule | Use `ec2-user` for Amazon Linux; confirm your current IP still matches the SG rule |
| SSH "permissions are too open" on key file | `demo-key.pem` is world-readable | Run `chmod 400 demo-key.pem` |
| Page shows default Nginx welcome instead of custom HTML | Cloud-init hasn't finished, or `write_files` path is wrong for the distro | Wait 2 minutes; check `/var/log/cloud-init-output.log` |
| `InvalidAMIID.NotFound` on `run-instances` | AMI ID is from a different region, or has been deprecated | Look up the current AMI via SSM (see Prerequisites) |
| `DependencyViolation` when deleting VPC | Resources still attached | Follow the cleanup order exactly; check the Console for lingering ENIs |
