#!/bin/bash
# Bulk secrets configuration script for RFP Platform repos
# Requires: gh CLI authenticated (`gh auth login`) and permission to set repo secrets
set -euo pipefail

ORG="billqhan"
REPOS=(rfp-ui rfp-lambdas rfp-java-api)

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI (gh) not installed. Install with: brew install gh" >&2
  exit 1
fi

echo "== RFP Platform Secrets Configuration =="
echo "Ensure you have AWS IAM credentials with least privilege configured."

read -p "AWS Access Key ID: " AWS_ACCESS_KEY_ID
read -s -p "AWS Secret Access Key: " AWS_SECRET_ACCESS_KEY; echo
read -p "AWS Region [us-east-1]: " AWS_REGION; AWS_REGION=${AWS_REGION:-us-east-1}

set_secret(){
  local repo=$1 name=$2 value=$3
  echo "Setting $name in $repo..."
  printf "%s" "$value" | gh secret set "$name" --repo "$ORG/$repo" >/dev/null
}

for repo in "${REPOS[@]}"; do
  set_secret "$repo" AWS_ACCESS_KEY_ID "$AWS_ACCESS_KEY_ID"
  set_secret "$repo" AWS_SECRET_ACCESS_KEY "$AWS_SECRET_ACCESS_KEY"
  set_secret "$repo" AWS_REGION "$AWS_REGION"
  echo "Common secrets done for $repo"
  echo "---"
done

# UI specific
read -p "UI Dev S3 Bucket: " S3_BUCKET_DEV
read -p "UI Prod S3 Bucket: " S3_BUCKET_PROD
read -p "UI Dev CloudFront Distribution ID: " CF_DEV
read -p "UI Prod CloudFront Distribution ID: " CF_PROD
set_secret rfp-ui S3_BUCKET_DEV "$S3_BUCKET_DEV"
set_secret rfp-ui S3_BUCKET_PROD "$S3_BUCKET_PROD"
set_secret rfp-ui CLOUDFRONT_DISTRIBUTION_ID_DEV "$CF_DEV"
set_secret rfp-ui CLOUDFRONT_DISTRIBUTION_ID_PROD "$CF_PROD"

# Java API specific
read -p "ECR Registry (e.g. 123456789012.dkr.ecr.us-east-1.amazonaws.com): " ECR_REG
read -p "EKS Dev Cluster Name: " EKS_DEV
read -p "EKS Prod Cluster Name: " EKS_PROD
set_secret rfp-java-api ECR_REGISTRY "$ECR_REG"
set_secret rfp-java-api EKS_CLUSTER_NAME_DEV "$EKS_DEV"
set_secret rfp-java-api EKS_CLUSTER_NAME_PROD "$EKS_PROD"

echo "Secrets configured. Verify with: gh secret list --repo $ORG/rfp-ui"
echo "Next: Create 'development' and 'production' environments in each repository settings."
echo "Done ✅"
