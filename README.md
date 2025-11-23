# RFP Infrastructure

Infrastructure as Code and API Contracts for the RFP Response Platform.

## Overview

This repository contains:
- **CloudFormation Templates**: AWS infrastructure definitions
- **Helm Charts**: Kubernetes deployment configurations  
- **Deployment Scripts**: Automated deployment utilities
- **API Contracts**: OpenAPI specifications and event schemas

## Repository Structure

```
.
├── cloudformation/         # AWS CloudFormation templates
│   ├── core/              # Core infrastructure (VPC, IAM, etc.)
│   ├── services/          # Service-specific stacks
│   └── outputs/           # Published stack outputs (gitignored)
├── helm/                  # Helm charts for Kubernetes
│   └── rfp-java-api/     # Java API Helm chart
├── scripts/               # Deployment and utility scripts
│   ├── deploy-infra.sh   # Infrastructure deployment
│   └── publish-outputs.sh # Publish stack outputs
└── rfp-contracts/         # API contracts and schemas
    ├── openapi/          # OpenAPI specifications
    ├── events/           # Event schemas (SQS, SNS, EventBridge)
    └── README.md         # Contract documentation
```

## Getting Started

### Prerequisites

- AWS CLI configured with appropriate credentials
- kubectl (for Kubernetes deployments)
- Helm 3+ (for Helm deployments)

### Deploying Infrastructure

Deploy the complete infrastructure stack to AWS:

```bash
# Deploy to development environment
./scripts/deploy-infra.sh dev

# Deploy to production environment
./scripts/deploy-infra.sh prod

# Optionally specify custom templates bucket and SAM API key
./scripts/deploy-infra.sh dev my-templates-bucket my-sam-api-key
```

The deployment script will:
1. 🪣 Create or verify S3 templates bucket
2. 📤 Upload CloudFormation templates to S3
3. 🏗️ Deploy master CloudFormation stack (with nested stacks)
4. ☁️ Optionally deploy CloudFront distribution for UI
5. 📝 Publish stack outputs for downstream services

**What gets deployed:**
- S3 buckets for data storage and UI hosting
- DynamoDB tables for opportunities and matches
- Lambda functions and IAM roles
- SQS queues and SNS topics
- EventBridge rules for scheduling
- VPC and networking (if configured)

### Publishing Outputs

After infrastructure deployment, publish stack outputs for downstream services:

```bash
./scripts/publish-outputs.sh dev
```

This creates `cloudformation/outputs/dev.json` with:
- API Gateway endpoints
- S3 bucket names
- DynamoDB table names
- Lambda function ARNs
- CloudFront distribution details

**Downstream services** (rfp-ui, rfp-java-api, rfp-lambdas) consume these outputs for configuration.

## Contracts

API contracts are versioned and published separately. See [rfp-contracts/README.md](rfp-contracts/README.md) for details.

### Using Contracts in Downstream Services

Services should consume contracts as dependencies:
- Pin to a specific contract version
- Run contract tests in CI
- Update contracts through PRs to this repo

## Versioning

- Infrastructure changes follow semantic versioning
- Tag releases when deploying to production
- Contracts are versioned independently (see rfp-contracts/)

## Contributing

1. Create a feature branch
2. Make changes and test locally
3. Submit a PR with description of changes
4. Ensure CI passes before merging

## Environment Outputs

After deployment, this repo publishes environment configuration files consumed by:
- `rfp-ui` - React frontend
- `rfp-java-api` - Spring Boot backend
- `rfp-lambdas` - Python Lambda functions

Example output structure:
```json
{
  "version": "1.0.0",
  "environment": "dev",
  "apiGatewayUrl": "https://xxx.execute-api.us-east-1.amazonaws.com/dev",
  "javaApiUrl": "http://xxx.elb.amazonaws.com",
  "s3Buckets": {
    "ui": "dev-sam-website-dev",
    "data": "dev-sam-data-in-dev"
  },
  "cloudfront": {
    "distributionId": "E123456",
    "domain": "xxx.cloudfront.net"
  }
}
```

## License

Proprietary - All Rights Reserved
