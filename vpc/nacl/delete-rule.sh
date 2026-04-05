#!/usr/bin/env bash
# =============================================================================
# Script:      delete-nacl-rule.sh
# Description: Removes an inbound DENY rule from an existing Network ACL
#              to re-enable access from the previously blocked IP address.
# Usage:       ./delete-nacl-rule.sh [rule-number]
# Example:     ./delete-nacl-rule.sh
#              ./delete-nacl-rule.sh 100
# Requirements:
#               - AWS CLI installed and configured
#               - IAM permissions: ec2:DeleteNetworkAclEntry,
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
# 3. LOOK UP SUBNET AND NACL IDs
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
# 4. VALIDATE RULE EXISTS
# Description: Check the rule exists before attempting to delete it to
#              avoid a confusing AWS error message.
# =============================================================================

echo "Looking up rule $RULE_NUMBER..."
RULE_CHECK=$(
    aws ec2 describe-network-acls \
    --network-acl-ids $NACL_ID \
    --query "NetworkAcls[0].Entries[?RuleNumber==\`$RULE_NUMBER\` && Egress==\`false\`].RuleNumber" \
    --region $REGION \
    --output text
)

if [ "$RULE_CHECK" == "None" ] || [ -z "$RULE_CHECK" ]; then
    echo "ERROR: Inbound rule '$RULE_NUMBER' not found in NACL '$NACL_ID'. Aborting."
    exit 1
fi

# Show the rule that will be deleted so the user knows what is being removed
echo "Found rule to delete:"
aws ec2 describe-network-acls \
    --network-acl-ids $NACL_ID \
    --query "NetworkAcls[0].Entries[?RuleNumber==\`$RULE_NUMBER\` && Egress==\`false\`]" \
    --region $REGION \
    --output table

# =============================================================================
# 5. DELETE NACL RULE
# Description: Deletes the inbound rule at the specified rule number,
#              re-enabling traffic from the previously blocked IP address.
#              --ingress targets inbound rules only.
# =============================================================================

echo "Deleting inbound rule $RULE_NUMBER from NACL $NACL_ID..."
aws ec2 delete-network-acl-entry \
    --network-acl-id $NACL_ID \
    --ingress \
    --rule-number $RULE_NUMBER \
    --region $REGION
echo "Rule deleted."

# =============================================================================
# 6. VERIFY RULE WAS DELETED
# =============================================================================

echo "Verifying rule was removed..."
VERIFY=$(
    aws ec2 describe-network-acls \
    --network-acl-ids $NACL_ID \
    --query "NetworkAcls[0].Entries[?RuleNumber==\`$RULE_NUMBER\` && Egress==\`false\`].RuleNumber" \
    --region $REGION \
    --output text
)

if [ -z "$VERIFY" ]; then
    echo "Verified — rule $RULE_NUMBER no longer exists."
else
    echo "WARNING: Rule $RULE_NUMBER may still exist. Please verify manually."
fi

# =============================================================================
# SUMMARY
# =============================================================================
echo ""
echo "============================="
echo "NACL rule deletion complete!"
echo "============================="
printf "%-20s %s\n" "Region:"      "$REGION"
printf "%-20s %s\n" "Subnet ID:"   "$SUBNET_ID"
printf "%-20s %s\n" "NACL ID:"     "$NACL_ID"
printf "%-20s %s\n" "Rule number:" "$RULE_NUMBER"
printf "%-20s %s\n" "Direction:"   "Inbound"
printf "%-20s %s\n" "Status:"      "✓ removed — traffic re-enabled"
echo "============================="

export AWS_CLI_AUTO_PROMPT=on
