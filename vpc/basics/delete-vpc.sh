#!/usr/bin/env bash
# =============================================================================
# Script:      delete-vpc.sh
# Description: Cleans up all AWS resources created by create-vpc.sh:
#               - Route (0.0.0.0/0 to IGW)
#               - Subnet association from Route Table
#               - Public Subnet
#               - Internet Gateway (detach + delete)
#               - VPC
#
# Usage:       ./delete-vpc.sh
# Requirements:
#               - AWS CLI installed and configured
#               - IAM permissions: ec2:DeleteVpc, ec2:DeleteInternetGateway,
#                 ec2:DetachInternetGateway, ec2:DeleteSubnet,
#                 ec2:DeleteRoute, ec2:DisassociateRouteTable
# Note:        Resources must be deleted in reverse order of creation,
#              as AWS enforces dependency constraints between resources.
# =============================================================================

set -e  # Exit immediately if any command fails

export AWS_CLI_AUTO_PROMPT=off

# =============================================================================
# 1. RETRIEVE ACCOUNT DETAILS
# =============================================================================

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Account ID: $ACCOUNT_ID"

REGION=$(aws configure get region)
echo "Region: $REGION"


# =============================================================================
# 2. LOOK UP RESOURCE IDs
# Description: Fetch all IDs by their Name tags before deleting anything,
#              so we can fail early if any resource is not found.
# =============================================================================

echo "Looking up resources..."

# Look up VPC by Name tag
VPC_ID=$(
    aws ec2 describe-vpcs \
    --filters "Name=tag:Name,Values=MyVPC" \
    --query "Vpcs[0].VpcId" \
    --region $REGION \
    --output text
)
if [ "$VPC_ID" == "None" ] || [ -z "$VPC_ID" ]; then
    echo "ERROR: VPC 'MyVPC' not found. Aborting."
    exit 1
fi
echo "VPC ID:         $VPC_ID"

# Look up IGW by Name tag
IGW_ID=$(
    aws ec2 describe-internet-gateways \
    --filters "Name=tag:Name,Values=MyIGW" \
    --query "InternetGateways[0].InternetGatewayId" \
    --region $REGION \
    --output text
)
if [ "$IGW_ID" == "None" ] || [ -z "$IGW_ID" ]; then
    echo "ERROR: Internet Gateway 'MyIGW' not found. Aborting."
    exit 1
fi
echo "IGW ID:         $IGW_ID"

# Look up Subnet by Name tag
SUBNET_ID=$(
    aws ec2 describe-subnets \
    --filters "Name=tag:Name,Values=MyPublicSubnet" "Name=vpc-id,Values=$VPC_ID" \
    --query "Subnets[0].SubnetId" \
    --region $REGION \
    --output text
)
if [ "$SUBNET_ID" == "None" ] || [ -z "$SUBNET_ID" ]; then
    echo "ERROR: Subnet 'MyPublicSubnet' not found. Aborting."
    exit 1
fi
echo "Subnet ID:      $SUBNET_ID"

# Look up the main Route Table associated with the VPC
ROUTE_TABLE_ID=$(
    aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=association.main,Values=true" \
    --query "RouteTables[0].RouteTableId" \
    --region $REGION \
    --output text
)
if [ "$ROUTE_TABLE_ID" == "None" ] || [ -z "$ROUTE_TABLE_ID" ]; then
    echo "ERROR: Route Table for VPC '$VPC_ID' not found. Aborting."
    exit 1
fi
echo "Route Table ID: $ROUTE_TABLE_ID"

# Look up the subnet association ID (needed to disassociate the subnet)
ASSOCIATION_ID=$(
    aws ec2 describe-route-tables \
    --route-table-ids $ROUTE_TABLE_ID \
    --query "RouteTables[0].Associations[?SubnetId=='$SUBNET_ID'].RouteTableAssociationId" \
    --region $REGION \
    --output text
)
if [ "$ASSOCIATION_ID" == "None" ] || [ -z "$ASSOCIATION_ID" ]; then
    echo "ERROR: Route Table Association for Subnet '$SUBNET_ID' not found. Aborting."
    exit 1
fi
echo "Association ID: $ASSOCIATION_ID"


# =============================================================================
# 3. DELETE ROUTE
# Description: Remove the default internet route (0.0.0.0/0 → IGW) from the
#              route table before deleting other resources.
# =============================================================================

echo ""
echo "Deleting internet route (0.0.0.0/0) from route table..."
aws ec2 delete-route \
    --route-table-id $ROUTE_TABLE_ID \
    --destination-cidr-block "0.0.0.0/0" \
    --region $REGION
echo "Route deleted."


# =============================================================================
# 4. DISASSOCIATE SUBNET FROM ROUTE TABLE
# Description: The subnet must be disassociated from the route table before
#              the subnet itself can be deleted.
# =============================================================================

echo "Disassociating subnet from route table..."
aws ec2 disassociate-route-table \
    --association-id $ASSOCIATION_ID \
    --region $REGION
echo "Subnet disassociated."


# =============================================================================
# 5. DELETE SUBNET
# Description: Delete the public subnet. All ENIs and instances within must
#              already be terminated before this step.
# =============================================================================

echo "Deleting subnet $SUBNET_ID..."
aws ec2 delete-subnet \
    --subnet-id $SUBNET_ID \
    --region $REGION
echo "Subnet deleted."


# =============================================================================
# 6. DETACH AND DELETE INTERNET GATEWAY
# Description: The IGW must be detached from the VPC before it can be deleted.
#              These are two separate API calls.
# =============================================================================

echo "Detaching IGW from VPC..."
aws ec2 detach-internet-gateway \
    --internet-gateway-id $IGW_ID \
    --vpc-id $VPC_ID \
    --region $REGION
echo "IGW detached."

echo "Deleting IGW $IGW_ID..."
aws ec2 delete-internet-gateway \
    --internet-gateway-id $IGW_ID \
    --region $REGION
echo "IGW deleted."


# =============================================================================
# 7. DELETE VPC
# Description: The VPC can only be deleted once all attached resources
#              (subnets, IGW, route tables, security groups, etc.) are removed.
#              The default route table and default security group are
#              automatically deleted along with the VPC.
# =============================================================================

echo "Deleting VPC $VPC_ID..."
aws ec2 delete-vpc \
    --vpc-id $VPC_ID \
    --region $REGION
echo "VPC deleted."


# =============================================================================
# SUMMARY
# =============================================================================
echo ""
echo "============================="
echo "VPC cleanup complete!"
echo "============================="
printf "%-20s %s\n" "Account ID:"     "$ACCOUNT_ID"
printf "%-20s %s\n" "Region:"         "$REGION"
printf "%-20s %s  ✓ deleted\n" "VPC ID:"         "$VPC_ID"
printf "%-20s %s  ✓ deleted\n" "IGW ID:"         "$IGW_ID"
printf "%-20s %s  ✓ deleted\n" "Subnet ID:"      "$SUBNET_ID"
printf "%-20s %s  ✓ deleted (with VPC)\n" "Route Table ID:" "$ROUTE_TABLE_ID"
echo "============================="

export AWS_CLI_AUTO_PROMPT=on
