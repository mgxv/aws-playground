#!/usr/bin/env bash
# =============================================================================
# Script:      cleanup.sh
# Description: Tears down all AWS resources created by create-vpc.sh and
#              create-stack.sh in the correct order:
#               - CloudFormation stack (EC2, IAM role, instance profile,
#                 security group)
#               - Internet Gateway (detach + delete)
#               - Subnet
#               - Route Table routes and associations
#               - VPC
#
# Usage:       ./cleanup.sh
# Requirements:
#               - AWS CLI installed and configured
#               - IAM permissions: ec2:DeleteVpc, ec2:DeleteSubnet,
#                 ec2:DeleteInternetGateway, ec2:DetachInternetGateway,
#                 ec2:DeleteRoute, ec2:DisassociateRouteTable,
#                 cloudformation:DeleteStack, iam:RemoveRoleFromInstanceProfile
# =============================================================================

set -e  # Exit immediately if any command fails

export AWS_CLI_AUTO_PROMPT=off

REGION=$(aws configure get region)
echo "Region: $REGION"

# =============================================================================
# 1. LOOK UP RESOURCE IDs
# Description: Fetch all IDs before deleting anything so we can fail early
#              if any resource is not found.
# =============================================================================

echo "Looking up resources..."

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
# 2. DELETE CLOUDFORMATION STACK
# Description: Deletes the EC2 instance, security group, IAM role and
#              instance profile created by create-stack.sh. The IAM role
#              is manually detached first to prevent the deletion error
#              "must remove roles from instance profile first".
# =============================================================================

echo ""
echo "Removing IAM role from instance profile..."
aws iam remove-role-from-instance-profile \
    --instance-profile-name EC2SSMInstanceProfile \
    --role-name EC2SSMRole 2>/dev/null || echo "IAM role already detached, skipping."

echo "Deleting CloudFormation stack..."
aws cloudformation delete-stack \
    --stack-name MyEC2Stack \
    --region $REGION

echo "Waiting for stack deletion to complete..."
aws cloudformation wait stack-delete-complete \
    --stack-name MyEC2Stack \
    --region $REGION
echo "Stack deleted."


# =============================================================================
# 3. DELETE ROUTE
# Description: Remove the default internet route (0.0.0.0/0 → IGW) from
#              the route table before deleting other resources.
# =============================================================================

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
#              already be terminated before this step — handled by the
#              CloudFormation stack deletion above.
# =============================================================================

echo "Deleting subnet $SUBNET_ID..."
aws ec2 delete-subnet \
    --subnet-id $SUBNET_ID \
    --region $REGION
echo "Subnet deleted."


# =============================================================================
# 6. DETACH AND DELETE INTERNET GATEWAY
# Description: The IGW must be detached from the VPC before it can be
#              deleted. These are two separate API calls.
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
#              are removed. The default route table and default security
#              group are automatically deleted along with the VPC.
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
echo "Cleanup complete!"
echo "============================="
printf "%-20s %s  ✓ deleted\n" "Stack:"         "MyEC2Stack"
printf "%-20s %s  ✓ deleted\n" "VPC ID:"         "$VPC_ID"
printf "%-20s %s  ✓ deleted\n" "IGW ID:"         "$IGW_ID"
printf "%-20s %s  ✓ deleted\n" "Subnet ID:"      "$SUBNET_ID"
printf "%-20s %s  ✓ deleted (with VPC)\n" "Route Table ID:" "$ROUTE_TABLE_ID"
echo "============================="

export AWS_CLI_AUTO_PROMPT=on
