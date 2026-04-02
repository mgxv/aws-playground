#!/usr/bin/env bash

# ─────────────────────────────────────────────
# Helper functions
# ─────────────────────────────────────────────
LABEL_WIDTH=12

success(){ printf "[OK]   %-${LABEL_WIDTH}s %s\n" "$1" "$2"; }
error()  { printf "[MISS] %-${LABEL_WIDTH}s %s\n" "$1" "not found"; }

echo "─────────────────────────────────────────────"
echo " Dependency Version Check"
echo "─────────────────────────────────────────────"

# AWS CLI
if command -v aws &>/dev/null; then
  success "aws" "$(aws --version 2>&1)"
else
  error "aws"
fi

# Node.js
if command -v node &>/dev/null; then
  success "node" "$(node --version)"
else
  error "node"
fi

# npm
if command -v npm &>/dev/null; then
  success "npm" "$(npm --version)"
else
  error "npm"
fi

# CDK
if command -v cdk &>/dev/null; then
  success "cdk" "$(cdk --version)"
else
  error "cdk"
fi

# Go
if command -v go &>/dev/null; then
  success "go" "$(go version)"
else
  error "go"
fi

# Terraform
if command -v terraform &>/dev/null; then
  success "terraform" "$(terraform version | head -1)"
else
  error "terraform"
fi

# Pulumi
if command -v pulumi &>/dev/null; then
  success "pulumi" "$(pulumi version)"
else
  error "pulumi"
fi

echo "─────────────────────────────────────────────"
