#!/usr/bin/env bash
# =============================================================================
# Script:      create-stack.sh
# Description: Looks up VPC and Subnet IDs by name tag and deploys the
#              CloudFormation stack for the EC2 instance with Apache.
# Usage:       ./create-stack.sh
# Requirements:
#               - AWS CLI installed and configured
#               - IAM permissions: ec2:DescribeVpcs, ec2:DescribeSubnets,
#                 cloudformation:CreateStack, iam:CreateRole,
#                 iam:CreateInstanceProfile, iam:AttachRolePolicy
# =============================================================================

set -e  # Exit immediately if any command fails

export AWS_CLI_AUTO_PROMPT=off

REGION=$(aws configure get region)
echo "Region: $REGION"

# =============================================================================
# 1. LOOK UP VPC ID
# =============================================================================

VPC_ID=$(
    aws ec2 describe-vpcs \
    --filters "Name=tag:Name,Values=MyVPC" \
    --query "Vpcs[0].VpcId" \
    --region $REGION \
    --output text
)

if [ "$VPC_ID" == "None" ] || [ -z "$VPC_ID" ]; then
    echo "ERROR: VPC 'MyVPC' not found. Have you run create-vpc.sh?"
    exit 1
fi
echo "VPC ID: $VPC_ID"

# =============================================================================
# 2. LOOK UP SUBNET ID
# =============================================================================

SUBNET_ID=$(
    aws ec2 describe-subnets \
    --filters "Name=tag:Name,Values=MyPublicSubnet" "Name=vpc-id,Values=$VPC_ID" \
    --query "Subnets[0].SubnetId" \
    --region $REGION \
    --output text
)

if [ "$SUBNET_ID" == "None" ] || [ -z "$SUBNET_ID" ]; then
    echo "ERROR: Subnet 'MyPublicSubnet' not found. Have you run create-vpc.sh?"
    exit 1
fi
echo "Subnet ID: $SUBNET_ID"

# =============================================================================
# 3. DEPLOY CLOUDFORMATION STACK
# =============================================================================

echo "Deploying CloudFormation stack..."
aws cloudformation create-stack \
    --stack-name MyEC2Stack \
    --template-body file://template.yaml \
    --capabilities CAPABILITY_NAMED_IAM \
    --region $REGION \
    --parameters \
        ParameterKey=VPCID,ParameterValue=$VPC_ID \
        ParameterKey=SubnetId,ParameterValue=$SUBNET_ID \
    --query 'StackId' \
    --output text > /dev/null

# =============================================================================
# 4. MONITOR STACK CREATION
# =============================================================================

echo "Waiting for stack creation to complete..."
aws cloudformation wait stack-create-complete \
    --stack-name MyEC2Stack \
    --region $REGION

# =============================================================================
# 5. GET EC2 INSTANCE PUBLIC IPv4
# Description: Looks up the EC2 instance created by the stack using the
#              Name tag and retrieves its public IPv4 address.
# =============================================================================

# Retrieve the instance ID by filtering on the Name tag
INSTANCE_ID=$(
    aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=MyEC2Instance" \
              "Name=instance-state-name,Values=running" \
    --query "Reservations[0].Instances[0].InstanceId" \
    --region $REGION \
    --output text
)

if [ "$INSTANCE_ID" == "None" ] || [ -z "$INSTANCE_ID" ]; then
    echo "ERROR: EC2 instance 'MyEC2Instance' not found."
    exit 1
fi

# Retrieve the public IPv4 address of the instance
PUBLIC_IP=$(
    aws ec2 describe-instances \
    --instance-ids $INSTANCE_ID \
    --query "Reservations[0].Instances[0].PublicIpAddress" \
    --region $REGION \
    --output text
)

if [ "$PUBLIC_IP" == "None" ] || [ -z "$PUBLIC_IP" ]; then
    echo "WARNING: No public IPv4 assigned to instance $INSTANCE_ID."
fi

# =============================================================================
# SUMMARY
# =============================================================================
echo ""
echo "============================="
echo "Stack deployment complete!"
echo "============================="
printf "%-20s %s\n" "Region:"      "$REGION"
printf "%-20s %s\n" "Stack:"       "MyEC2Stack"
printf "%-20s %s\n" "VPC ID:"      "$VPC_ID"
printf "%-20s %s\n" "Subnet ID:"   "$SUBNET_ID"
printf "%-20s %s\n" "Instance ID:" "$INSTANCE_ID"
printf "%-20s %s\n" "Public IPv4:" "$PUBLIC_IP"
echo "============================="
echo ""
echo "Test Apache is running:"
echo "  curl http://$PUBLIC_IP"
echo "============================="

export AWS_CLI_AUTO_PROMPT=on
