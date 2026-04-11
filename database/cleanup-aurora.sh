#!/usr/bin/env bash
# =============================================================================
# cleanup-aurora.sh — Tears down everything created by create-aurora.sh.
# Resources are deleted in reverse order of creation.
# =============================================================================
set -e
export AWS_CLI_AUTO_PROMPT=off

REGION=$(aws configure get region)

# Look up all resources by tag (same pattern as create script)
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=demo-db-vpc" \
  --query "Vpcs[0].VpcId" --region $REGION --output text)

if [ "$VPC_ID" == "None" ] || [ -z "$VPC_ID" ]; then
    echo "Nothing to clean up (VPC not found)."; exit 0
fi
echo "Tearing down VPC $VPC_ID and all associated resources..."

# -----------------------------------------------------------------------------
# 1. Delete writer instance
# -----------------------------------------------------------------------------
echo "Deleting writer instance..."
aws rds delete-db-instance \
  --db-instance-identifier demo-aurora-writer \
  --skip-final-snapshot --region $REGION > /dev/null 2>&1 || true
aws rds wait db-instance-deleted --db-instance-identifier demo-aurora-writer --region $REGION 2>/dev/null || true

# -----------------------------------------------------------------------------
# 2. Delete cluster
# -----------------------------------------------------------------------------
echo "Deleting cluster..."
aws rds delete-db-cluster \
  --db-cluster-identifier demo-aurora-cluster \
  --skip-final-snapshot --region $REGION > /dev/null 2>&1 || true
aws rds wait db-cluster-deleted --db-cluster-identifier demo-aurora-cluster --region $REGION 2>/dev/null || true

# -----------------------------------------------------------------------------
# 3. DB subnet group
# -----------------------------------------------------------------------------
echo "Deleting DB subnet group..."
aws rds delete-db-subnet-group --db-subnet-group-name demo-db-subnet-group --region $REGION 2>/dev/null || true

# -----------------------------------------------------------------------------
# 4. Security group
# -----------------------------------------------------------------------------
SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=demo-db-sg" \
  --query "SecurityGroups[0].GroupId" --region $REGION --output text 2>/dev/null || echo "")
if [ -n "$SG_ID" ] && [ "$SG_ID" != "None" ]; then
    echo "Deleting security group $SG_ID..."
    aws ec2 delete-security-group --group-id $SG_ID --region $REGION
fi

# -----------------------------------------------------------------------------
# 5. Route table (disassociate, then delete)
# -----------------------------------------------------------------------------
RTB_ID=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=demo-db-rtb" \
  --query "RouteTables[0].RouteTableId" --region $REGION --output text)
if [ -n "$RTB_ID" ] && [ "$RTB_ID" != "None" ]; then
    echo "Disassociating route table $RTB_ID..."
    for ASSOC in $(aws ec2 describe-route-tables --route-table-ids $RTB_ID \
        --query 'RouteTables[0].Associations[?Main==`false`].RouteTableAssociationId' \
        --region $REGION --output text); do
        aws ec2 disassociate-route-table --association-id $ASSOC --region $REGION
    done
    aws ec2 delete-route-table --route-table-id $RTB_ID --region $REGION
fi

# -----------------------------------------------------------------------------
# 6. Internet gateway
# -----------------------------------------------------------------------------
IGW_ID=$(aws ec2 describe-internet-gateways --filters "Name=tag:Name,Values=demo-db-igw" \
  --query "InternetGateways[0].InternetGatewayId" --region $REGION --output text)
if [ -n "$IGW_ID" ] && [ "$IGW_ID" != "None" ]; then
    echo "Detaching and deleting IGW $IGW_ID..."
    aws ec2 detach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID --region $REGION
    aws ec2 delete-internet-gateway --internet-gateway-id $IGW_ID --region $REGION
fi

# -----------------------------------------------------------------------------
# 7. Subnets
# -----------------------------------------------------------------------------
for TAG in demo-db-subnet-a demo-db-subnet-b; do
    SUBNET_ID=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=$TAG" \
      --query "Subnets[0].SubnetId" --region $REGION --output text)
    if [ -n "$SUBNET_ID" ] && [ "$SUBNET_ID" != "None" ]; then
        echo "Deleting subnet $SUBNET_ID..."
        aws ec2 delete-subnet --subnet-id $SUBNET_ID --region $REGION
    fi
done

# -----------------------------------------------------------------------------
# 8. VPC
# -----------------------------------------------------------------------------
echo "Deleting VPC $VPC_ID..."
aws ec2 delete-vpc --vpc-id $VPC_ID --region $REGION

rm -f ./aurora-info.env

echo ""
echo "============================="
echo "Aurora teardown complete!"
echo "============================="
printf "%-20s %s\n" "Writer Instance:"  "demo-aurora-writer"
printf "%-20s %s\n" "Cluster:"          "demo-aurora-cluster"
printf "%-20s %s\n" "DB Subnet Group:"  "demo-db-subnet-group"
printf "%-20s %s\n" "Security Group:"   "${SG_ID:-demo-db-sg}"
printf "%-20s %s\n" "Route Table:"      "${RTB_ID:-demo-db-rtb}"
printf "%-20s %s\n" "IGW:"              "${IGW_ID:-demo-db-igw}"
printf "%-20s %s\n" "Subnet A:"         "demo-db-subnet-a"
printf "%-20s %s\n" "Subnet B:"         "demo-db-subnet-b"
printf "%-20s %s\n" "VPC:"              "$VPC_ID"
echo "============================="

export AWS_CLI_AUTO_PROMPT=on
