#!/usr/bin/env bash

# ─────────────────────────────────────────────
# Helper functions
# ─────────────────────────────────────────────
LABEL_WIDTH=12

success(){ printf "[OK]   %-${LABEL_WIDTH}s %s\n" "$1" "$2"; }
fail()   { printf "[FAIL] %-${LABEL_WIDTH}s %s\n" "$1" "$2"; }

echo "─────────────────────────────────────────────"
echo " Connectivity & Credentials Check"
echo "─────────────────────────────────────────────"

# GitHub SSH
if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
  success "github" "SSH authenticated"
else
  fail "github" "SSH authentication failed"
fi

export AWS_CLI_AUTO_PROMPT=off

# AWS credentials
if aws sts get-caller-identity &>/dev/null; then
  ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
  REGION=$(aws configure get region)
  USER=$(aws sts get-caller-identity --query Arn --output text)
  success "aws account" "$ACCOUNT"
  success "aws region" "$REGION"
  success "aws arn" "$USER"
else
  fail "aws creds" "no credentials found"
fi

export AWS_CLI_AUTO_PROMPT=on

echo "─────────────────────────────────────────────"
