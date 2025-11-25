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
│   └── deploy-cloudfront.sh # CloudFront distribution
└── rfp-contracts/         # API contracts and schemas
```

## 🚀 Quick Start - Complete Deployment

The easiest way to deploy the entire platform (infrastructure + services):

```bash
# Deploy everything to development environment
./scripts/deploy-complete.sh dev

# Deploy everything to production environment
./scripts/deploy-complete.sh prod
```

### What Gets Deployed (6 Steps)

1. **Infrastructure** - VPC, S3 buckets, DynamoDB tables, Lambda functions, SQS queues
2. **Application Load Balancer** - ALB with target groups and security groups
3. **Java API** - ECS Fargate service with Docker container
4. **CloudFront** - CDN distribution with S3 origin and API proxy
5. **Lambda Functions** - Deploy Lambda code packages
6. **React UI** - Build and deploy UI to S3 with CloudFront invalidation

### Skip Specific Steps

You can skip steps if they're already deployed:

```bash
# Skip infrastructure and ALB, deploy only services
SKIP_INFRA=true SKIP_ALB=true ./scripts/deploy-complete.sh dev

# Skip everything except UI
SKIP_INFRA=true SKIP_ALB=true SKIP_JAVA=true SKIP_CLOUDFRONT=true SKIP_LAMBDA=true ./scripts/deploy-complete.sh dev
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

## Architecture

- **Infrastructure**: CloudFormation nested stacks (VPC, S3, DynamoDB, Lambda, SQS, SNS)
- **Java API**: ECS Fargate with Application Load Balancer
- **UI**: React app served via CloudFront + S3
- **Lambda Functions**: Python-based serverless functions
- **CloudFront**: CDN with `/api/*` proxy to ALB

## API Contracts

API contracts (OpenAPI specs and event schemas) are in `rfp-contracts/`. See [rfp-contracts/README.md](rfp-contracts/README.md) for details.

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues and solutions.

## License

Proprietary - All Rights Reserved
