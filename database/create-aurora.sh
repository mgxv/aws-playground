#!/usr/bin/env bash
# =============================================================================
# Script:      create-aurora.sh
# Description: Provisions a complete AWS network stack and an Amazon Aurora
#              PostgreSQL-Compatible cluster with a writer instance.
#
#              Resources created:
#                - VPC (10.0.0.0/16) with DNS hostnames/support enabled
#                - Internet Gateway attached to the VPC
#                - Two subnets in different AZs (10.0.1.0/24, 10.0.2.0/24)
#                - Route table with default route to IGW, associated w/ both
#                - Security group allowing PostgreSQL (5432) from current IP
#                - DB Subnet Group spanning both subnets
#                - Aurora PostgreSQL cluster (engine 16.4)
#                - db.t3.medium writer instance (publicly accessible — demo)
#
# Usage:       ./create-aurora.sh
# Outputs:     Writes cluster endpoint + master password to ./aurora-info.env
# =============================================================================

set -e
export AWS_CLI_AUTO_PROMPT=off

# -----------------------------------------------------------------------------
# 1. ACCOUNT / REGION
# -----------------------------------------------------------------------------
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=$(aws configure get region)
echo "Account ID: $ACCOUNT_ID"
echo "Region:     $REGION"

# -----------------------------------------------------------------------------
# 2. CREATE VPC
# -----------------------------------------------------------------------------
echo "Creating VPC..."
aws ec2 create-vpc \
  --cidr-block "10.0.0.0/16" \
  --region $REGION \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=demo-db-vpc}]' \
  --query 'Vpc.VpcId' --output text > /dev/null

VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=demo-db-vpc" \
  --query "Vpcs[0].VpcId" --region $REGION --output text)

if [ "$VPC_ID" == "None" ] || [ -z "$VPC_ID" ]; then
    echo "ERROR: VPC creation failed. Aborting."; exit 1
fi
echo "VPC ID: $VPC_ID"

aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-support

# -----------------------------------------------------------------------------
# 3. INTERNET GATEWAY
# -----------------------------------------------------------------------------
echo "Creating Internet Gateway..."
aws ec2 create-internet-gateway \
  --region $REGION \
  --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=demo-db-igw}]' \
  --query 'InternetGateway.InternetGatewayId' --output text > /dev/null

IGW_ID=$(aws ec2 describe-internet-gateways \
  --filters "Name=tag:Name,Values=demo-db-igw" \
  --query "InternetGateways[0].InternetGatewayId" --region $REGION --output text)

if [ "$IGW_ID" == "None" ] || [ -z "$IGW_ID" ]; then
    echo "ERROR: IGW creation failed. Aborting."; exit 1
fi
echo "IGW ID: $IGW_ID"

aws ec2 attach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID --region $REGION

# -----------------------------------------------------------------------------
# 4. SUBNETS (two AZs — Aurora requirement)
# -----------------------------------------------------------------------------
echo "Creating subnet A..."
aws ec2 create-subnet \
  --vpc-id $VPC_ID --cidr-block "10.0.1.0/24" \
  --availability-zone "${REGION}a" --region $REGION \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=demo-db-subnet-a}]' \
  --query 'Subnet.SubnetId' --output text > /dev/null

SUBNET_A_ID=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=demo-db-subnet-a" \
  --query "Subnets[0].SubnetId" --region $REGION --output text)
echo "Subnet A ID: $SUBNET_A_ID"

echo "Creating subnet B..."
aws ec2 create-subnet \
  --vpc-id $VPC_ID --cidr-block "10.0.2.0/24" \
  --availability-zone "${REGION}b" --region $REGION \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=demo-db-subnet-b}]' \
  --query 'Subnet.SubnetId' --output text > /dev/null

SUBNET_B_ID=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=demo-db-subnet-b" \
  --query "Subnets[0].SubnetId" --region $REGION --output text)
echo "Subnet B ID: $SUBNET_B_ID"

# -----------------------------------------------------------------------------
# 5. ROUTE TABLE
# -----------------------------------------------------------------------------
echo "Creating route table..."
aws ec2 create-route-table --vpc-id $VPC_ID --region $REGION \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=demo-db-rtb}]' \
  --query 'RouteTable.RouteTableId' --output text > /dev/null

RTB_ID=$(aws ec2 describe-route-tables \
  --filters "Name=tag:Name,Values=demo-db-rtb" \
  --query "RouteTables[0].RouteTableId" --region $REGION --output text)
echo "Route Table ID: $RTB_ID"

aws ec2 create-route --route-table-id $RTB_ID \
  --destination-cidr-block "0.0.0.0/0" --gateway-id $IGW_ID \
  --region $REGION --query 'Return' --output text > /dev/null

aws ec2 associate-route-table --route-table-id $RTB_ID --subnet-id $SUBNET_A_ID --region $REGION --query 'AssociationId' --output text > /dev/null
aws ec2 associate-route-table --route-table-id $RTB_ID --subnet-id $SUBNET_B_ID --region $REGION --query 'AssociationId' --output text > /dev/null

# -----------------------------------------------------------------------------
# 6. SECURITY GROUP (PostgreSQL from current IP only)
# -----------------------------------------------------------------------------
echo "Creating security group..."
aws ec2 create-security-group \
  --group-name demo-db-sg \
  --description "Allow PostgreSQL access for Aurora demo" \
  --vpc-id $VPC_ID --region $REGION \
  --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=demo-db-sg}]' \
  --query 'GroupId' --output text > /dev/null

SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=demo-db-sg" \
  --query "SecurityGroups[0].GroupId" --region $REGION --output text)
echo "Security Group ID: $SG_ID"

MY_IP=$(curl -s https://checkip.amazonaws.com)
echo "Authorizing PostgreSQL (5432) from ${MY_IP}/32..."
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID --protocol tcp --port 5432 \
  --cidr "${MY_IP}/32" --region $REGION > /dev/null

# -----------------------------------------------------------------------------
# 7. DB SUBNET GROUP
# -----------------------------------------------------------------------------
echo "Creating DB subnet group..."
aws rds create-db-subnet-group \
  --db-subnet-group-name demo-db-subnet-group \
  --db-subnet-group-description "Subnet group for Aurora PostgreSQL demo" \
  --subnet-ids $SUBNET_A_ID $SUBNET_B_ID \
  --region $REGION > /dev/null

# -----------------------------------------------------------------------------
# 8. AURORA CLUSTER + WRITER
# -----------------------------------------------------------------------------
DB_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)

echo "Creating Aurora cluster (this takes a few minutes)..."
aws rds create-db-cluster \
  --db-cluster-identifier demo-aurora-cluster \
  --engine aurora-postgresql --engine-version 16.4 \
  --master-username dbadmin --master-user-password "$DB_PASSWORD" \
  --db-subnet-group-name demo-db-subnet-group \
  --vpc-security-group-ids $SG_ID \
  --database-name appdb \
  --backup-retention-period 1 --storage-encrypted \
  --region $REGION > /dev/null

echo "Creating writer instance..."
aws rds create-db-instance \
  --db-instance-identifier demo-aurora-writer \
  --db-cluster-identifier demo-aurora-cluster \
  --engine aurora-postgresql \
  --db-instance-class db.t3.medium \
  --publicly-accessible \
  --region $REGION > /dev/null

echo "Waiting for writer to become available (5-10 min)..."
aws rds wait db-instance-available --db-instance-identifier demo-aurora-writer --region $REGION

CLUSTER_ENDPOINT=$(aws rds describe-db-clusters \
  --db-cluster-identifier demo-aurora-cluster \
  --query 'DBClusters[0].Endpoint' --region $REGION --output text)

# -----------------------------------------------------------------------------
# Save connection info for test/cleanup scripts
# -----------------------------------------------------------------------------
cat > ./aurora-info.env <<EOF
export CLUSTER_ENDPOINT="$CLUSTER_ENDPOINT"
export DB_PASSWORD="$DB_PASSWORD"
export DB_USER="dbadmin"
export DB_NAME="appdb"
EOF
chmod 600 ./aurora-info.env

echo ""
echo "============================="
echo "Aurora setup complete!"
echo "============================="
printf "%-20s %s\n" "VPC ID:"           "$VPC_ID"
printf "%-20s %s\n" "Subnet A:"         "$SUBNET_A_ID"
printf "%-20s %s\n" "Subnet B:"         "$SUBNET_B_ID"
printf "%-20s %s\n" "Security Group:"   "$SG_ID"
printf "%-20s %s\n" "Cluster Endpoint:" "$CLUSTER_ENDPOINT"
printf "%-20s %s\n" "Master Password:"  "$DB_PASSWORD"
echo "============================="
echo "Connection info written to ./aurora-info.env"

export AWS_CLI_AUTO_PROMPT=on
