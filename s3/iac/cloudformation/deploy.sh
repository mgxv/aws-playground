#!/usr/bin/env bash

set -euo pipefail

# ─────────────────────────────────────────────
# Usage check
# Requires a stack name to be passed as the
# first argument e.g. ./deploy.sh my-stack
# ─────────────────────────────────────────────
if [ -z "${1:-}" ]; then
  echo "Usage: $0 <stack-name>"
  exit 1
fi

# ─────────────────────────────────────────────
# Disable auto-prompt to prevent interactive
# prompts from interrupting the script
# ─────────────────────────────────────────────
export AWS_CLI_AUTO_PROMPT=off

# ─────────────────────────────────────────────
# Resolve account ID and region
# || true prevents set -e from exiting if the
# command fails (e.g. region not configured)
# ─────────────────────────────────────────────
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Account ID: $ACCOUNT_ID"

REGION=$(aws configure get region || true)
REGION=${REGION:-us-east-1}  # fallback if not configured
echo "Region: $REGION"

# ─────────────────────────────────────────────
# Configuration
# Stack name is passed as the first argument
# ─────────────────────────────────────────────
STACK_NAME="$1"
TEMPLATE_FILE="$(dirname "$0")/template.yaml"

# ─────────────────────────────────────────────
# Helper functions
# ─────────────────────────────────────────────
log()  { echo "[INFO]  $*"; }
error(){ echo "[ERROR] $*" >&2; exit 1; }

# ─────────────────────────────────────────────
# Pre-flight checks
# Ensure AWS CLI is installed and the template
# file exists before proceeding
# ─────────────────────────────────────────────
command -v aws &>/dev/null || error "AWS CLI is not installed."
[[ -f "$TEMPLATE_FILE" ]] || error "Template file '$TEMPLATE_FILE' not found."

# ─────────────────────────────────────────────
# Validate template
# Catches syntax errors before deployment
# ─────────────────────────────────────────────
log "Validating CloudFormation template..."
aws cloudformation validate-template \
  --template-body file://"$TEMPLATE_FILE" \
  --region "$REGION" &>/dev/null \
  && log "Template is valid." \
  || error "Template validation failed."

# ─────────────────────────────────────────────
# Check if stack already exists
# Sets ACTION to "create" or "update" so the
# correct wait command can be used later
# ─────────────────────────────────────────────
if aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" &>/dev/null; then
  ACTION="update"
else
  ACTION="create"
fi

# ─────────────────────────────────────────────
# Deploy (create or update)
# --no-fail-on-empty-changeset prevents the
# script from exiting if nothing has changed
# ─────────────────────────────────────────────
log "Starting stack ${ACTION}: '$STACK_NAME'..."
aws cloudformation deploy \
  --stack-name "$STACK_NAME" \
  --template-file "$TEMPLATE_FILE" \
  --region "$REGION" \
  --capabilities CAPABILITY_NAMED_IAM \
  --no-fail-on-empty-changeset

# ─────────────────────────────────────────────
# Wait for completion
# Blocks until the stack reaches a stable state
# ─────────────────────────────────────────────
log "Waiting for stack to reach a stable state..."
aws cloudformation wait "stack-${ACTION}-complete" \
  --stack-name "$STACK_NAME" \
  --region "$REGION"

# ─────────────────────────────────────────────
# Print stack outputs
# ─────────────────────────────────────────────
log "Deployment complete. Stack outputs:"
aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  --query "Stacks[0].Outputs" \
  --output table

# ─────────────────────────────────────────────
# Re-enable auto-prompt
# ─────────────────────────────────────────────
export AWS_CLI_AUTO_PROMPT=on

log "Done!"
