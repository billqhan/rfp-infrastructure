# RFP Infrastructure

Infrastructure as Code for the RFP Response Platform.

## Overview

This repository contains CloudFormation templates, deployment scripts, and API contracts for the complete RFP platform infrastructure.

## Repository Structure

```
.
├── cloudformation/         # AWS CloudFormation templates
│   ├── core/              # Core infrastructure (VPC, S3, Lambda, etc.)
│   └── services/          # Service-specific stacks (ALB, CloudFront)
├── scripts/               # Deployment automation scripts
│   ├── deploy-complete.sh # Complete platform deployment (recommended)
│   ├── deploy-infra.sh    # Infrastructure only
│   ├── deploy-alb.sh      # Application Load Balancer
│   ├── deploy-cloudfront.sh # CloudFront distribution
│   └── cleanup-aws.sh     # Complete cleanup of all AWS resources
└── rfp-contracts/         # API contracts and schemas
```

## 🚀 Quick Start - Complete Deployment

The easiest way to deploy the entire platform (infrastructure + services):

```bash
# Deploy everything to development environment
cd scripts
./deploy-complete.sh dev

# Deploy everything to production environment
./deploy-complete.sh prod
```

### What Gets Deployed (6 Steps)

1. **Infrastructure** (~8-10 min) - VPC, S3 buckets, DynamoDB tables, Lambda functions, SQS queues
2. **Application Load Balancer** (~2-3 min) - ALB with target groups and security groups
3. **Java API** (~6-8 min) - ECS Fargate service with Docker container
4. **CloudFront** (~15-20 min) - CDN distribution with S3 origin and API proxy
5. **Lambda Functions** (~0 min) - Lambda shells created (code deployment via CI/CD)
6. **React UI** (~2-3 min) - Build and deploy UI to S3 with CloudFront invalidation

**Total Time:** ~35-45 minutes

### Skip Specific Steps

You can skip steps if they're already deployed:

```bash
# Skip infrastructure and ALB, deploy only services
SKIP_INFRA=true SKIP_ALB=true ./deploy-complete.sh dev

# Skip everything except CloudFront and UI
SKIP_INFRA=true SKIP_ALB=true SKIP_JAVA=true SKIP_LAMBDA=true ./deploy-complete.sh dev

# Deploy only UI
SKIP_INFRA=true SKIP_ALB=true SKIP_JAVA=true SKIP_CLOUDFRONT=true SKIP_LAMBDA=true ./deploy-complete.sh dev
```

## 🧪 Fresh Deployment Test

To test a complete fresh deployment from scratch:

### Step 1: Complete Cleanup (30-40 minutes)

```bash
cd scripts

# Run cleanup (requires typing "DELETE" to confirm)
./cleanup-aws.sh
```

The cleanup script removes:
- CloudFormation stacks (master + 8 nested + ALB)
- ALB and target groups
- ECS clusters, services, and task definitions
- ECR repositories
- Lambda functions
- S3 buckets (with versioned objects)
- CloudFront distributions
- CloudWatch log groups
- Security groups
- IAM roles

**Important:** CloudFront distributions take 15-20 minutes to disable. If cleanup completes but CloudFront still exists:

```bash
# Wait 15-20 minutes, then run again
./cleanup-aws.sh
```

### Step 2: Verify Complete Cleanup

```bash
# Check all resources are gone
aws s3 ls | grep rfp
aws ecs list-clusters --region us-east-1
aws ecr describe-repositories --region us-east-1
aws lambda list-functions --region us-east-1 --query 'Functions[?contains(FunctionName, `rfp`)].FunctionName'
aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE --query 'StackSummaries[?contains(StackName, `rfp`)].StackName'
aws elbv2 describe-load-balancers --query 'LoadBalancers[?contains(LoadBalancerName, `dev`)].LoadBalancerName'
aws cloudfront list-distributions --query 'DistributionList.Items[?contains(Comment, `han`)].{Id:Id,Status:Status}'
```

All commands should return empty or "None".

### Step 3: Fresh Deployment

```bash
# Full deployment from scratch
./deploy-complete.sh dev
```

### Step 4: Verification

#### Infrastructure Check
```bash
aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE --query 'StackSummaries[?contains(StackName, `rfp`)].StackName' --output table
```
Expected: 10 stacks (1 master + 8 nested + 1 ALB)

#### Java API Health
```bash
# Get ALB URL from stack
ALB_URL=$(aws cloudformation describe-stacks --stack-name rfp-dev-java-api-alb --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerUrl`].OutputValue' --output text)

# Test health endpoint
curl $ALB_URL/api/actuator/health
```
Expected: `{"status":"UP"}`

#### ECS Service
```bash
aws ecs describe-services --cluster dev-ecs-cluster --services dev-java-api-service --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount}' --output table
```
Expected: Status=ACTIVE, Running=1, Desired=1

#### CloudFront & UI
```bash
# Get CloudFront URL
CF_URL=$(aws cloudformation describe-stacks --stack-name rfp-han-dev-cloudfront-ui --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontDistributionUrl`].OutputValue' --output text)

echo "CloudFront URL: $CF_URL"

# Test (wait 2-3 min for cache after first deployment)
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" $CF_URL
```
Expected: HTTP Status: 200

#### Lambda Functions
```bash
aws lambda list-functions --query 'Functions[?contains(FunctionName, `rfp-han-dev`)].{Name:FunctionName,Runtime:Runtime,Status:State}' --output table
```
Expected: 8 functions (all Python 3.11)

#### End-to-End Test

```bash
# Open UI in browser
open https://$(aws cloudformation describe-stacks --stack-name rfp-han-dev-cloudfront-ui --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontDistributionUrl`].OutputValue' --output text)

# Test API through CloudFront
curl https://$(aws cloudformation describe-stacks --stack-name rfp-han-dev-cloudfront-ui --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontDistributionUrl`].OutputValue' --output text)/api/actuator/health
```

## 🔧 Individual Component Deployment

If you need to deploy components separately:

### 1. Infrastructure Only

```bash
./scripts/deploy-infra.sh dev
```

### 2. Application Load Balancer

```bash
./scripts/deploy-alb.sh dev
```

### 3. CloudFront Distribution

```bash
./scripts/deploy-cloudfront.sh dev
```

## Prerequisites

- **AWS CLI** configured with appropriate credentials
- **Docker** for building Java API containers
- **Node.js 18+** and npm for UI builds
- **Maven 3.9+** and **Java 21** for Java API builds
- **jq** for JSON processing in scripts

## Architecture

- **Infrastructure**: CloudFormation nested stacks (VPC, S3, DynamoDB, Lambda, SQS, SNS)
- **Java API**: ECS Fargate (1024 CPU / 2048 MB dev, 2048 CPU / 4096 MB prod)
- **UI**: React app served via CloudFront + S3
- **Lambda Functions**: 8 Python 3.11 functions for SAM.gov data processing
- **CloudFront**: CDN with `/api/*` proxy to ALB
- **Region**: us-east-1

## Deployed Resources

After successful deployment, you'll have:

### Development Environment
- **Java API (ALB)**: `http://dev-java-api-alb-*.us-east-1.elb.amazonaws.com/api`
- **CloudFront**: `https://*.cloudfront.net`
- **ECS Cluster**: `dev-ecs-cluster`
- **S3 UI Bucket**: `rfp-han-dev-ui`
- **ECR Repository**: `dev-rfp-java-api`

### CloudFormation Stacks
- `rfp-dev-master` (master stack with 8 nested stacks)
- `rfp-dev-java-api-alb` (ALB stack)
- `rfp-han-dev-cloudfront-ui` (CloudFront stack)

## Known Issues & Workarounds

### Issue 1: Lambda Deployment Script Missing
**Status:** Lambda functions exist but code deployment is manual  
**Workaround:** Use GitHub Actions CI/CD to deploy Lambda code  
**Impact:** Lambda shells created by CloudFormation, code deployed separately

### Issue 2: CloudFront Deletion Requires Two Passes
**Status:** CloudFront must be disabled (15-20 min) before deletion  
**Workaround:** Run cleanup-aws.sh twice with 20-min wait  
**Fix:** Already handled in cleanup-aws.sh script with retry logic

### Issue 3: Verification Script Timing
**Status:** Fixed - now waits up to 3 minutes for ECS tasks  
**Fix:** Updated verify-deployment.sh with retry loop

## API Contracts

API contracts (OpenAPI specs and event schemas) are in `rfp-contracts/`. See [rfp-contracts/README.md](rfp-contracts/README.md) for details.

## CI/CD

GitHub Actions workflows handle automated deployments:
- **rfp-java-api**: ECS deployment workflow
- **rfp-lambdas**: Lambda function deployment workflow
- **rfp-ui**: S3/CloudFront deployment workflow

See [CI-CD-PIPELINES-COMPLETE.md](CI-CD-PIPELINES-COMPLETE.md) for details.

## Troubleshooting

Common issues and solutions:

### Deployment Fails at Verification Step
- **Cause:** ECS tasks take time to start
- **Fix:** Script now waits up to 3 minutes with retry loop
- **Manual Check:** `aws ecs describe-tasks --cluster dev-ecs-cluster --tasks <task-arn>`

### CloudFront Returns 403 or 404
- **Cause:** Cache not populated yet
- **Fix:** Wait 2-3 minutes after first deployment
- **Manual Clear:** Invalidate cache in CloudFront console

### S3 Bucket Deletion Fails
- **Cause:** Versioned objects or delete markers
- **Fix:** cleanup-aws.sh now deletes all versions automatically
- **Manual:** Use AWS Console to empty bucket with versions

### ALB Health Check Fails
- **Cause:** Security group or task not ready
- **Fix:** Check task logs in CloudWatch `/ecs/dev-java-api`
- **Verify:** `curl http://<alb-url>/api/actuator/health`

## License

Proprietary - All Rights Reserved
