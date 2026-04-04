#!/usr/bin/env bash
# =============================================================================
# Script:      create-vpc.sh
# Description: Creates a fully functional AWS VPC with the following resources:
#               - VPC (172.1.0.0/16)
#               - Internet Gateway (IGW) attached to the VPC
#               - Public Subnet (172.1.1.0/24) with auto-assign public IP
#               - Route Table with a default route to the IGW
#
# Usage:       ./create-vpc.sh
# Requirements:
#               - AWS CLI installed and configured
#               - IAM permissions: ec2:CreateVpc, ec2:CreateInternetGateway,
#                 ec2:AttachInternetGateway, ec2:CreateSubnet,
#                 ec2:CreateRoute, ec2:AssociateRouteTable
# =============================================================================

set -e  # Exit immediately if any command fails

export AWS_CLI_AUTO_PROMPT=off

# =============================================================================
# 1. RETRIEVE ACCOUNT DETAILS
# =============================================================================

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Account ID: $ACCOUNT_ID"

# Fetch the default region from the local AWS CLI config (~/.aws/config)
REGION=$(aws configure get region)
echo "Region: $REGION"


# =============================================================================
# 2. CREATE VPC
# Description: Creates a VPC with the CIDR block 172.1.0.0/16, which provides
#              65,536 private IP addresses (172.1.0.0 - 172.1.255.255)
# =============================================================================

echo "Creating VPC..."
aws ec2 create-vpc \
  --cidr-block "172.1.0.0/16" \
  --region $REGION \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=MyVPC}]' \
  --query 'Vpc.VpcId' \
  --output text > /dev/null

# Retrieve the VPC ID by filtering on its Name tag
VPC_ID=$(
    aws ec2 describe-vpcs \
    --filters "Name=tag:Name,Values=MyVPC" \
    --query "Vpcs[0].VpcId" \
    --region $REGION \
    --output text
)
echo "VPC ID: $VPC_ID"

# Enable DNS hostnames so that EC2 instances launched in this VPC
# receive a public DNS hostname (e.g. ec2-xx-xx-xx-xx.compute-1.amazonaws.com)
echo "Enabling DNS hostnames on VPC..."
aws ec2 modify-vpc-attribute \
    --vpc-id $VPC_ID \
    --enable-dns-hostnames

# Enable DNS resolution so that instances can resolve public DNS hostnames
# to IP addresses using the Amazon-provided DNS server
echo "Enabling DNS support on VPC..."
aws ec2 modify-vpc-attribute \
    --vpc-id $VPC_ID \
    --enable-dns-support


# =============================================================================
# 3. CREATE AND ATTACH INTERNET GATEWAY (IGW)
# Description: An IGW allows resources in public subnets to communicate with
#              the internet. It performs NAT for instances with public IPs.
# =============================================================================

echo "Creating Internet Gateway..."
aws ec2 create-internet-gateway \
    --region $REGION \
    --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=MyIGW}]' \
    --query 'InternetGateway.InternetGatewayId' \
    --output text > /dev/null

# Retrieve the IGW ID by filtering on its Name tag
IGW_ID=$(
    aws ec2 describe-internet-gateways \
    --filters "Name=tag:Name,Values=MyIGW" \
    --query "InternetGateways[0].InternetGatewayId" \
    --region $REGION \
    --output text
)
echo "IGW ID: $IGW_ID"

# Attach the IGW to the VPC — a VPC can only have one IGW attached at a time
echo "Attaching IGW to VPC..."
aws ec2 attach-internet-gateway \
    --internet-gateway-id $IGW_ID \
    --vpc-id $VPC_ID \
    --region $REGION


# =============================================================================
# 4. CREATE PUBLIC SUBNET
# Description: Creates a subnet with CIDR 172.1.1.0/24, which provides
#              256 IPs (172.1.1.0 - 172.1.1.255). AWS reserves 5 of these,
#              leaving 251 usable IPs.
# =============================================================================

echo "Creating public subnet..."
aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block "172.1.1.0/24" \
    --region $REGION \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=MyPublicSubnet}]' \
    --query 'Subnet.SubnetId' \
    --output text > /dev/null

# Retrieve the Subnet ID by filtering on VPC ID and CIDR block
SUBNET_ID=$(
    aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=cidrBlock,Values=172.1.1.0/24" \
    --query "Subnets[0].SubnetId" \
    --region $REGION \
    --output text
)
echo "Subnet ID: $SUBNET_ID"

# Auto-assign a public IPv4 address to any EC2 instance launched in this subnet,
# making it reachable from the internet without manual Elastic IP assignment
echo "Enabling auto-assign public IP on subnet..."
aws ec2 modify-subnet-attribute \
    --subnet-id $SUBNET_ID \
    --map-public-ip-on-launch


# =============================================================================
# 5. CONFIGURE ROUTE TABLE
# Description: The main route table controls traffic routing for all subnets
#              in the VPC that are not explicitly associated with another table.
#              We add a default route (0.0.0.0/0) pointing to the IGW so that
#              outbound internet traffic is allowed from the public subnet.
# =============================================================================

# Retrieve the main (default) route table automatically created with the VPC
ROUTE_TABLE_ID=$(
    aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=association.main,Values=true" \
    --query "RouteTables[0].RouteTableId" \
    --region $REGION \
    --output text
)
echo "Route Table ID: $ROUTE_TABLE_ID"

# Explicitly associate the public subnet with the main route table
echo "Associating subnet with route table..."
aws ec2 associate-route-table \
    --route-table-id $ROUTE_TABLE_ID \
    --subnet-id $SUBNET_ID \
    --region $REGION \
    --query 'AssociationId' \
    --output text > /dev/null

# Add a default route: any traffic destined for the internet (0.0.0.0/0)
# is forwarded to the IGW, enabling outbound internet access
echo "Adding internet route to route table..."
aws ec2 create-route \
    --route-table-id $ROUTE_TABLE_ID \
    --destination-cidr-block "0.0.0.0/0" \
    --gateway-id $IGW_ID \
    --region $REGION \
    --query 'Return' \
    --output text > /dev/null


# =============================================================================
# SUMMARY
# =============================================================================
echo ""
echo "============================="
echo "VPC setup complete!"
echo "============================="
printf "%-20s %s\n" "Account ID:"     "$ACCOUNT_ID"
printf "%-20s %s\n" "Region:"         "$REGION"
printf "%-20s %s\n" "VPC ID:"         "$VPC_ID"
printf "%-20s %s\n" "IGW ID:"         "$IGW_ID"
printf "%-20s %s\n" "Subnet ID:"      "$SUBNET_ID"
printf "%-20s %s\n" "Route Table ID:" "$ROUTE_TABLE_ID"
echo "============================="

export AWS_CLI_AUTO_PROMPT=on