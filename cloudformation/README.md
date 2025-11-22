# CloudFormation Templates

This directory contains AWS CloudFormation Infrastructure as Code templates for the RFP Response Platform.

## Directory Structure

### Core Infrastructure (`core/`)
- `master-template.yaml` - Root template that orchestrates all stack deployments
- `main-template.yaml` - Main infrastructure coordination template
- `iam-security-policies.yaml` - IAM roles, policies, and security configurations
- `iam-security-policies-simple.yaml` - Simplified IAM setup for development
- `parameters-dev.json` - Development environment parameters
- `parameters-prod.json` - Production environment parameters

### Service-Specific Templates (`services/`)
- `lambda-functions.yaml` - Lambda function definitions, configurations, and permissions
- `lambda-functions-simple.yaml` - Simplified Lambda setup for development
- `dynamodb-tables.yaml` - DynamoDB table definitions with indexes and configurations
- `dynamodb-tables-simple.yaml` - Simplified DynamoDB setup for development
- `s3-bucket-policies.yaml` - S3 bucket policies and access controls
- `s3-event-notifications.yaml` - S3 event notifications for triggering workflows
- `eventbridge-rules.yaml` - EventBridge rules for event-driven workflows
- `monitoring-alerting.yaml` - CloudWatch alarms, dashboards, and SNS notifications
- `template.yaml` - General purpose service template

### Stack Outputs (`outputs/`)
Generated JSON files containing stack outputs for consumption by service repositories.

## Migrated Infrastructure

These templates were migrated from the original monorepo on **November 21, 2024**. The infrastructure supports:
- Lambda-based workflow processing
- DynamoDB data storage
- S3-based storage and event triggers
- EventBridge scheduled workflows
- CloudWatch monitoring and alerting

## Usage

Deploy infrastructure using the deployment script:

```bash
# From repository root
./scripts/deploy-infra.sh <environment> <stack-name>

# Examples - Deploy core infrastructure first
./scripts/deploy-infra.sh dev master-template
./scripts/deploy-infra.sh dev iam-security-policies

# Then deploy service stacks
./scripts/deploy-infra.sh dev lambda-functions
./scripts/deploy-infra.sh dev dynamodb-tables
./scripts/deploy-infra.sh prod lambda-functions
```

## Deployment Order

1. **Core Infrastructure** (deploy first):
   - master-template.yaml
   - iam-security-policies.yaml

2. **Service Infrastructure** (deploy after core):
   - dynamodb-tables.yaml
   - s3-bucket-policies.yaml
   - lambda-functions.yaml
   - s3-event-notifications.yaml
   - eventbridge-rules.yaml
   - monitoring-alerting.yaml

## Template Guidelines

- Use semantic versioning for template changes
- Include comprehensive parameter descriptions
- Export all values needed by services as stack outputs
- Follow AWS CloudFormation best practices
- Include DeletionPolicy for stateful resources (S3, DynamoDB)
- Use Conditions for environment-specific configurations
- Reference rfp-contracts OpenAPI specs for API Gateway configurations

## Parameters

Each template uses environment-specific parameters from `parameters-<env>.json`:
- `Environment` - dev, staging, or prod
- `BucketPrefix` - Prefix for S3 bucket names
- `SAMApiKey` - SAM.gov API key (stored in AWS Secrets Manager)
- Stack-specific parameters defined in individual templates

## Outputs

All templates export stack outputs to enable cross-stack references:
- Resource ARNs (Lambda functions, DynamoDB tables, S3 buckets)
- API endpoints and URLs
- IAM role ARNs
- Queue URLs

Use `./scripts/publish-outputs.sh <environment>` to generate consolidated output files.

## Monitoring

The `monitoring-alerting.yaml` template creates:
- CloudWatch alarms for Lambda errors and throttling
- DynamoDB capacity alarms
- SNS topics for alert notifications
- CloudWatch dashboard for operational visibility

See `MONITORING.md` for detailed monitoring configuration.

## Security

IAM roles follow least-privilege principles. See `SECURITY.md` for security best practices and compliance considerations.
