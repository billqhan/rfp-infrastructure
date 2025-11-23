# GitHub Secrets Configuration Guide

This document lists all GitHub secrets that need to be configured for the CI/CD pipelines to work.

## Common Secrets (All Repositories)

These secrets should be configured in **all three repositories**: rfp-ui, rfp-lambdas, rfp-java-api

### AWS Credentials
```
AWS_ACCESS_KEY_ID
  Description: AWS Access Key ID for deployment
  Required: Yes
  Example: AKIAIOSFODNN7EXAMPLE

AWS_SECRET_ACCESS_KEY
  Description: AWS Secret Access Key for deployment
  Required: Yes
  Example: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY

AWS_REGION
  Description: AWS Region for resources
  Required: Yes
  Example: us-east-1
```

## Repository-Specific Secrets

### rfp-ui

```
S3_BUCKET_DEV
  Description: S3 bucket name for development UI hosting
  Required: Yes (for dev deployments)
  Example: rfp-ui-dev-12345

S3_BUCKET_PROD
  Description: S3 bucket name for production UI hosting
  Required: Yes (for prod deployments)
  Example: rfp-ui-prod-12345

CLOUDFRONT_DISTRIBUTION_ID_DEV
  Description: CloudFront distribution ID for development
  Required: Yes (for dev deployments)
  Example: E1234567890ABC

CLOUDFRONT_DISTRIBUTION_ID_PROD
  Description: CloudFront distribution ID for production
  Required: Yes (for prod deployments)
  Example: E0987654321XYZ
```

### rfp-lambdas

No additional secrets required beyond common AWS credentials.

Lambda function names follow convention:
- Development: `dev-{function-name}`
- Production: `prod-{function-name}`

Examples:
- `dev-sam-gov-daily-download`
- `prod-sam-json-processor`

### rfp-java-api

```
ECR_REGISTRY
  Description: ECR registry URL for Docker images
  Required: Yes
  Example: 123456789012.dkr.ecr.us-east-1.amazonaws.com

# EKS Deployment Secrets (ci-cd.yml workflow)
EKS_CLUSTER_NAME_DEV
  Description: EKS cluster name for development
  Required: Yes (for EKS dev deployments)
  Example: rfp-platform-dev

EKS_CLUSTER_NAME_PROD
  Description: EKS cluster name for production
  Required: Yes (for EKS prod deployments)
  Example: rfp-platform-prod

# ECS Deployment Secrets (ci-cd-ecs.yml workflow)
ECS_CLUSTER_DEV
  Description: ECS cluster name for development
  Required: Yes (for ECS dev deployments)
  Example: dev-ecs-cluster

ECS_CLUSTER_PROD
  Description: ECS cluster name for production
  Required: Yes (for ECS prod deployments)
  Example: prod-ecs-cluster

ECS_SERVICE_DEV
  Description: ECS service name for development
  Required: Yes (for ECS dev deployments)
  Example: dev-java-api-service

ECS_SERVICE_PROD
  Description: ECS service name for production
  Required: Yes (for ECS prod deployments)
  Example: prod-java-api-service

ECS_TASK_FAMILY_DEV
  Description: ECS task definition family for development
  Required: Yes (for ECS dev deployments)
  Example: dev-java-api-task

ECS_TASK_FAMILY_PROD
  Description: ECS task definition family for production
  Required: Yes (for ECS prod deployments)
  Example: prod-java-api-task

API_ENDPOINT_PROD
  Description: Production API endpoint URL for smoke tests (optional)
  Required: No
  Example: https://api.rfp-platform.example.com
```

## GitHub Environments

Create these environments in each repository's settings:

### rfp-ui
- **development**: For S3/CloudFront dev deployments
- **production**: For S3/CloudFront prod deployments

### rfp-lambdas
- **development**: For Lambda dev deployments
- **production**: For Lambda prod deployments

### rfp-java-api
- **development**: For EKS dev deployments
- **production**: For EKS prod deployments
- **development-ecs**: For ECS dev deployments
- **production-ecs**: For ECS prod deployments

### Environment Configuration

**development / development-ecs**
- Protection rules: None (optional: require approval)
- Environment secrets: Can override common secrets with dev-specific values
- URL: Set to development environment URL

**production / production-ecs**
- Protection rules: 
  - ✅ Required reviewers (at least 1)
  - ✅ Wait timer (optional: 5 minutes)
  - ✅ Deployment branches: Only `main`
- Environment secrets: Can override common secrets with prod-specific values
- URL: Set to production environment URL

## How to Add Secrets

### Using GitHub Web UI

1. Navigate to repository settings
2. Go to **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Add name and value
5. Click **Add secret**

### Using GitHub CLI

```bash
# Set repository secret
gh secret set SECRET_NAME --repo OWNER/REPO

# Set environment secret
gh secret set SECRET_NAME --env ENVIRONMENT --repo OWNER/REPO

# Set secret from file
gh secret set SECRET_NAME < secret.txt --repo OWNER/REPO
```

## Configuration Script

Use this script to configure all secrets at once:

```bash
#!/bin/bash

# Configuration
GITHUB_ORG="billqhan"
AWS_REGION="us-east-1"

# AWS Credentials (set these first!)
read -p "AWS Access Key ID: " AWS_ACCESS_KEY_ID
read -sp "AWS Secret Access Key: " AWS_SECRET_ACCESS_KEY
echo

# Function to set secret
set_secret() {
    local repo=$1
    local name=$2
    local value=$3
    echo "Setting $name in $repo..."
    echo "$value" | gh secret set "$name" --repo "$GITHUB_ORG/$repo"
}

# Common secrets for all repos
for repo in rfp-ui rfp-lambdas rfp-java-api; do
    set_secret "$repo" "AWS_ACCESS_KEY_ID" "$AWS_ACCESS_KEY_ID"
    set_secret "$repo" "AWS_SECRET_ACCESS_KEY" "$AWS_SECRET_ACCESS_KEY"
    set_secret "$repo" "AWS_REGION" "$AWS_REGION"
done

# rfp-ui specific secrets
read -p "S3 Bucket (Dev): " S3_BUCKET_DEV
read -p "S3 Bucket (Prod): " S3_BUCKET_PROD
read -p "CloudFront Distribution ID (Dev): " CF_ID_DEV
read -p "CloudFront Distribution ID (Prod): " CF_ID_PROD

set_secret "rfp-ui" "S3_BUCKET_DEV" "$S3_BUCKET_DEV"
set_secret "rfp-ui" "S3_BUCKET_PROD" "$S3_BUCKET_PROD"
set_secret "rfp-ui" "CLOUDFRONT_DISTRIBUTION_ID_DEV" "$CF_ID_DEV"
set_secret "rfp-ui" "CLOUDFRONT_DISTRIBUTION_ID_PROD" "$CF_ID_PROD"

# rfp-java-api specific secrets
read -p "ECR Registry URL: " ECR_REGISTRY

# EKS secrets (for ci-cd.yml)
read -p "EKS Cluster Name (Dev): " EKS_DEV
read -p "EKS Cluster Name (Prod): " EKS_PROD

# ECS secrets (for ci-cd-ecs.yml)
read -p "ECS Cluster (Dev): " ECS_CLUSTER_DEV
read -p "ECS Cluster (Prod): " ECS_CLUSTER_PROD
read -p "ECS Service (Dev): " ECS_SERVICE_DEV
read -p "ECS Service (Prod): " ECS_SERVICE_PROD
read -p "ECS Task Family (Dev): " ECS_TASK_FAMILY_DEV
read -p "ECS Task Family (Prod): " ECS_TASK_FAMILY_PROD

set_secret "rfp-java-api" "ECR_REGISTRY" "$ECR_REGISTRY"
set_secret "rfp-java-api" "EKS_CLUSTER_NAME_DEV" "$EKS_DEV"
set_secret "rfp-java-api" "EKS_CLUSTER_NAME_PROD" "$EKS_PROD"
set_secret "rfp-java-api" "ECS_CLUSTER_DEV" "$ECS_CLUSTER_DEV"
set_secret "rfp-java-api" "ECS_CLUSTER_PROD" "$ECS_CLUSTER_PROD"
set_secret "rfp-java-api" "ECS_SERVICE_DEV" "$ECS_SERVICE_DEV"
set_secret "rfp-java-api" "ECS_SERVICE_PROD" "$ECS_SERVICE_PROD"
set_secret "rfp-java-api" "ECS_TASK_FAMILY_DEV" "$ECS_TASK_FAMILY_DEV"
set_secret "rfp-java-api" "ECS_TASK_FAMILY_PROD" "$ECS_TASK_FAMILY_PROD"

echo "✅ All secrets configured!"
```

## Verification

After adding secrets, verify they are configured:

```bash
# List secrets for a repository
gh secret list --repo billqhan/rfp-ui

# Expected output for rfp-ui:
# AWS_ACCESS_KEY_ID                     Updated 2024-11-21
# AWS_SECRET_ACCESS_KEY                 Updated 2024-11-21
# AWS_REGION                            Updated 2024-11-21
# S3_BUCKET_DEV                         Updated 2024-11-21
# S3_BUCKET_PROD                        Updated 2024-11-21
# CLOUDFRONT_DISTRIBUTION_ID_DEV        Updated 2024-11-21
# CLOUDFRONT_DISTRIBUTION_ID_PROD       Updated 2024-11-21
```

## IAM Permissions Required

The AWS credentials need the following permissions:

### rfp-ui Deployment
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::rfp-ui-*",
        "arn:aws:s3:::rfp-ui-*/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "cloudfront:CreateInvalidation",
        "cloudfront:GetInvalidation"
      ],
      "Resource": "*"
    }
  ]
}
```

### rfp-lambdas Deployment
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "lambda:UpdateFunctionCode",
        "lambda:GetFunction",
        "lambda:PublishVersion",
        "lambda:UpdateAlias",
        "lambda:CreateAlias",
        "lambda:ListVersionsByFunction"
      ],
      "Resource": "arn:aws:lambda:*:*:function:*-sam-*"
    }
  ]
}
```

### rfp-java-api Deployment
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "eks:DescribeCluster",
        "eks:ListClusters"
      ],
      "Resource": "*"
    }
  ]
}
```

## Security Best Practices

1. **Use IAM Roles with Least Privilege**: Create dedicated IAM users for CI/CD with minimal required permissions

2. **Rotate Credentials Regularly**: Update AWS access keys every 90 days

3. **Use Environment Secrets for Sensitive Values**: Keep production secrets in environment-specific configuration

4. **Enable Secret Scanning**: GitHub will automatically scan for exposed secrets

5. **Audit Secret Access**: Review GitHub Actions logs to ensure secrets are not being exposed

6. **Use OIDC for AWS Authentication** (Advanced):
   Instead of static credentials, configure GitHub OIDC provider:
   ```yaml
   - uses: aws-actions/configure-aws-credentials@v4
     with:
       role-to-assume: arn:aws:iam::123456789012:role/GitHubActionsRole
       aws-region: us-east-1
   ```

## Troubleshooting

### Secret Not Found
**Problem**: Workflow fails with "secret not found"

**Solution**: Verify secret name matches exactly (case-sensitive) and is added to correct repository

### Invalid AWS Credentials
**Problem**: AWS API calls fail with authentication errors

**Solution**: 
1. Verify credentials are correct
2. Check IAM user has required permissions
3. Ensure credentials haven't expired

### CloudFront Distribution Not Found
**Problem**: CloudFront invalidation fails

**Solution**: Verify distribution ID is correct and exists in the specified AWS account

### EKS Cluster Access Denied
**Problem**: Cannot update kubeconfig or deploy to EKS

**Solution**: Ensure IAM user has `eks:DescribeCluster` permission and is added to EKS cluster's aws-auth ConfigMap

---

**Next Steps**: After configuring secrets, test the CI/CD pipeline by creating a pull request or pushing to develop branch.
