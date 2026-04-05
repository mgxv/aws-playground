#!/usr/bin/env bash
# =============================================================================
# Script:      create-nacl-rule.sh
# Description: Adds an inbound DENY rule to an existing Network ACL to block
#              all traffic from the current machine's public IP address.
# Usage:       ./create-nacl-rule.sh [rule-number]
# Example:     ./create-nacl-rule.sh
#              ./create-nacl-rule.sh 100
# Requirements:
#               - AWS CLI installed and configured
#               - IAM permissions: ec2:CreateNetworkAclEntry,
#                 ec2:DescribeNetworkAcls
# =============================================================================

set -e  # Exit immediately if any command fails

export AWS_CLI_AUTO_PROMPT=off

# =============================================================================
# 1. PARSE ARGUMENTS
# =============================================================================

RULE_NUMBER="${1:-90}"  # Default to 90 if not provided

# =============================================================================
# 2. RETRIEVE ACCOUNT DETAILS
# =============================================================================

REGION=$(aws configure get region)
echo "Region: $REGION"

# =============================================================================
# 3. GET LOCAL PUBLIC IP
# Description: Fetches the current machine's public IP address automatically
#              so it never needs to be hardcoded or passed as an argument.
# =============================================================================

echo "Fetching local public IP..."
LOCAL_IP=$(curl -s https://checkip.amazonaws.com)

if [ -z "$LOCAL_IP" ]; then
    echo "ERROR: Could not determine local public IP. Aborting."
    exit 1
fi

CIDR_BLOCK="${LOCAL_IP}/32"
echo "Local IP: $LOCAL_IP"

# =============================================================================
# 4. LOOK UP SUBNET AND NACL IDs
# Description: Finds the subnet by name tag, then looks up the Network ACL
#              associated with that subnet automatically.
# =============================================================================

SUBNET_ID=$(
    aws ec2 describe-subnets \
    --filters "Name=tag:Name,Values=MyPublicSubnet" \
    --query "Subnets[0].SubnetId" \
    --region $REGION \
    --output text
)

if [ "$SUBNET_ID" == "None" ] || [ -z "$SUBNET_ID" ]; then
    echo "ERROR: Subnet 'MyPublicSubnet' not found. Have you run create-vpc.sh?"
    exit 1
fi
echo "Subnet ID: $SUBNET_ID"

NACL_ID=$(
    aws ec2 describe-network-acls \
    --filters "Name=association.subnet-id,Values=$SUBNET_ID" \
    --query "NetworkAcls[0].NetworkAclId" \
    --region $REGION \
    --output text
)

if [ "$NACL_ID" == "None" ] || [ -z "$NACL_ID" ]; then
    echo "ERROR: No Network ACL found for subnet '$SUBNET_ID'. Aborting."
    exit 1
fi
echo "NACL ID: $NACL_ID"

# =============================================================================
# 5. CREATE NACL DENY RULE
# Description: Adds an inbound DENY rule for all protocols and ports from
#              the local machine's public IP. The /32 CIDR block ensures
#              only that exact IP is blocked and nothing else.
# =============================================================================

echo "Adding DENY rule for $CIDR_BLOCK..."
aws ec2 create-network-acl-entry \
    --network-acl-id $NACL_ID \
    --ingress \
    --rule-number $RULE_NUMBER \
    --protocol -1 \
    --port-range From=0,To=65535 \
    --cidr-block $CIDR_BLOCK \
    --rule-action deny \
    --region $REGION
echo "Rule created."

# =============================================================================
# 6. VERIFY RULE WAS CREATED
# =============================================================================

echo "Verifying rule..."
aws ec2 describe-network-acls \
    --network-acl-ids $NACL_ID \
    --query "NetworkAcls[0].Entries[?RuleNumber==\`$RULE_NUMBER\`]" \
    --region $REGION \
    --output table

# =============================================================================
# SUMMARY
# =============================================================================
echo ""
echo "============================="
echo "NACL rule creation complete!"
echo "============================="
printf "%-20s %s\n" "Region:"      "$REGION"
printf "%-20s %s\n" "NACL ID:"     "$NACL_ID"
printf "%-20s %s\n" "Rule number:" "$RULE_NUMBER"
printf "%-20s %s\n" "CIDR block:"  "$CIDR_BLOCK"
printf "%-20s %s\n" "Direction:"   "Inbound"
printf "%-20s %s\n" "Action:"      "DENY"
printf "%-20s %s\n" "Protocol:"    "All"
printf "%-20s %s\n" "Ports:"       "All (0-65535)"
echo "============================="

export AWS_CLI_AUTO_PROMPT=on
