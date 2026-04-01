#!/usr/bin/env bash

# ─────────────────────────────────────────────
# Helper functions
# ─────────────────────────────────────────────
log()    { echo "[INFO]  $*"; }
success(){ echo "[OK]    $*"; }
error()  { echo "[MISS]  $*"; }

echo "─────────────────────────────────────────────"
echo " Dependency Version Check"
echo "─────────────────────────────────────────────"

# AWS CLI
if command -v aws &>/dev/null; then
  success "aws      $(aws --version 2>&1)"
else
  error "aws      not found"
fi

# Node.js
if command -v node &>/dev/null; then
  success "node     $(node --version)"
else
  error "node     not found"
fi

# npm
if command -v npm &>/dev/null; then
  success "npm      $(npm --version)"
else
  error "npm      not found"
fi

# CDK
if command -v cdk &>/dev/null; then
  success "cdk      $(cdk --version)"
else
  error "cdk      not found"
fi

# Go
if command -v go &>/dev/null; then
  success "go       $(go version)"
else
  error "go       not found"
fi

echo "─────────────────────────────────────────────"