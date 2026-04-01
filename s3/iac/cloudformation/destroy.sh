#!/usr/bin/env bash

set -euo pipefail

# ─────────────────────────────────────────────
# Usage check
# Requires a stack name to be passed as the
# first argument e.g. ./destroy.sh my-stack
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

# ─────────────────────────────────────────────
# Helper functions
# ─────────────────────────────────────────────
log()  { echo "[INFO]  $*"; }
error(){ echo "[ERROR] $*" >&2; exit 1; }

# ─────────────────────────────────────────────
# Pre-flight checks
# Ensure AWS CLI is installed before proceeding
# ─────────────────────────────────────────────
command -v aws &>/dev/null || error "AWS CLI is not installed."

# ─────────────────────────────────────────────
# Check if stack exists before attempting delete
# ─────────────────────────────────────────────
if ! aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" &>/dev/null; then
  error "Stack '$STACK_NAME' does not exist."
fi

# ─────────────────────────────────────────────
# Confirm before deleting
# Prompts the user to prevent accidental deletes
# ─────────────────────────────────────────────
read -r -p "[WARN]  Are you sure you want to delete stack '$STACK_NAME'? (y/N): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  log "Aborted."
  exit 0
fi

# ─────────────────────────────────────────────
# Delete stack
# ─────────────────────────────────────────────
log "Deleting stack '$STACK_NAME'..."
aws cloudformation delete-stack \
  --stack-name "$STACK_NAME" \
  --region "$REGION"

# ─────────────────────────────────────────────
# Wait for deletion to complete
# Blocks until the stack is fully deleted
# ─────────────────────────────────────────────
log "Waiting for stack deletion to complete..."
aws cloudformation wait stack-delete-complete \
  --stack-name "$STACK_NAME" \
  --region "$REGION"

# ─────────────────────────────────────────────
# Re-enable auto-prompt
# ─────────────────────────────────────────────
export AWS_CLI_AUTO_PROMPT=on

log "Stack '$STACK_NAME' deleted successfully."
