# VPC Architecture Diagram

## Architecture

```
                   ┌─────────────────┐
                   │    Internet     │
                   └────────┬────────┘
                            │
                   ┌────────▼───────────────┐
                   │  Internet Gateway      │
                   │  Step 2                │
                   └────────┬───────────────┘
                            │
┌───────────────────────────▼────────────────────────────┐
│  VPC — 172.1.0.0/16  (Step 1)                          │
│                                                        │
│  ┌──────────────────────────────────────────────────┐  │
│  │  Public Subnet — 172.1.1.0/24  (Step 3)          │  │
│  │                                                  │  │
│  │         ┌──────────────────────┐                 │  │
│  │         │   EC2 / Resources    │                 │  │
│  │         └──────────────────────┘                 │  │
│  │                                                  │  │
│  └──────────────────────────────────────────────────┘  │
│                            │                           │
│  ┌─────────────────────────▼──────────────────────┐    │
│  │  Route Table  (Step 4)                         │    │
│  │  0.0.0.0/0 → IGW                               │    │
│  └────────────────────────────────────────────────┘    │
│                                                        │
│  ┌─────────────────────┐  ┌─────────────────────┐      │
│  │  DNS hostnames      │  │  DNS support        │      │
│  │  Step 1             │  │  Step 1             │      │
│  └─────────────────────┘  └─────────────────────┘      │
│                                                        │
└────────────────────────────────────────────────────────┘
```

---

## Step-by-step explanation

### Step 1 — Create VPC
The VPC is your private, isolated network inside AWS. Everything else must
live inside it — you cannot create subnets, route tables, or gateways without
one. The CIDR block `172.1.0.0/16` defines the total IP address space
available, providing 65,536 private IP addresses (`172.1.0.0 - 172.1.255.255`).

Two DNS settings are also enabled at this step:

- **DNS support** enables the Amazon-provided DNS server (`169.254.169.253`)
  inside the VPC. Without it, nothing in the VPC can resolve domain names to
  IP addresses — not even basic lookups like resolving `google.com`.
- **DNS hostnames** makes AWS automatically assign a public DNS hostname to
  any EC2 instance that has a public IP (e.g.
  `ec2-54-234-12-88.compute-1.amazonaws.com`). Without this, instances only
  have a raw IP address, which breaks tools and services that expect a hostname
  (SSH configs, SSL certificates, load balancer health checks, etc.).

Both are disabled by default on custom VPCs, which is why the script enables
them explicitly right after creation.

---

### Step 2 — Create and attach Internet Gateway (IGW)
A freshly created VPC is completely isolated from the internet by design. The
IGW is the bridge that allows two-way communication between your VPC and the
public internet. It must be created as a standalone resource first, then
explicitly attached to the VPC — AWS keeps them separate so you can detach or
swap an IGW without destroying the VPC.

A VPC can only have one IGW attached at a time.

---

### Step 3 — Create public subnet
A VPC is just an address space — it has no subnets by default. The subnet
carves out a smaller block (`172.1.1.0/24`) within the VPC where resources
like EC2 instances actually live. This provides 256 IPs, of which AWS reserves
5, leaving 251 usable addresses.

Auto-assign public IP is enabled on the subnet so that any instance launched
into it automatically receives a public IP, making it reachable from the
internet without needing a manually assigned Elastic IP.

---

### Step 4 — Configure route table
Even with an IGW attached, traffic has nowhere to go without routing rules.
The route table tells the VPC where to send traffic. The default route
`0.0.0.0/0 → IGW` directs all internet-bound traffic to the IGW. The subnet
is explicitly associated with the route table so those rules apply to it.

Without this step the subnet would remain effectively private, even though the
IGW exists and is attached to the VPC.

The route table used is the default main route table automatically created by
AWS with the VPC — no additional route table is created by the script.
