# Step 2 Complete: Stack References and Infrastructure Templates

**Date:** November 21, 2024  
**Repository:** `rfp-infrastructure` (https://github.com/billqhan/rfp-infrastructure.git)

## Overview

Step 2 updates all stack references to work with the new repository structure and adds critical infrastructure templates for API Gateway and CloudFront distribution.

## Completed Tasks

### 1. Updated Master Template References ✅

**File:** `cloudformation/core/master-template.yaml`

Updated all nested stack TemplateURL references to point to new directory structure:

**Core Templates** (now in `core/`):
- `main-template.yaml` - Core infrastructure (S3, SQS)
- `iam-security-policies-simple.yaml` - IAM roles and policies

**Service Templates** (now in `services/`):
- `dynamodb-tables.yaml` - Database tables
- `lambda-functions.yaml` - Lambda function definitions
- `eventbridge-rules.yaml` - Scheduled rules
- `s3-bucket-policies.yaml` - S3 access policies
- `monitoring-alerting.yaml` - CloudWatch monitoring
- `s3-event-notifications.yaml` - S3 event triggers

All templates now use paths like: `${TemplatesBucketPrefix}core/main-template.yaml` and `${TemplatesBucketPrefix}services/lambda-functions.yaml`

### 2. Created API Gateway Template ✅

**File:** `cloudformation/services/api-gateway.yaml`

Comprehensive API Gateway REST API with full Lambda integration:

**Endpoints Implemented:**
- `GET /dashboard/metrics` - Dashboard metrics
- `GET /dashboard/activity` - Recent activity feed
- `GET /dashboard/charts/{type}` - Chart data by type
- `GET /dashboard/top-matches` - Top matching opportunities
- `POST /workflow/trigger` - Trigger workflow execution
- `GET /workflow/status/{id}` - Get workflow status
- `GET /opportunities` - List opportunities
- `GET /opportunities/{id}` - Get single opportunity
- `GET /reports` - List reports
- `GET /reports/{id}/download` - Download report

**Features:**
- ✅ CORS support with OPTIONS methods on all endpoints
- ✅ AWS_PROXY Lambda integration for all endpoints
- ✅ Lambda permissions for API Gateway invocation
- ✅ Proper path parameters for dynamic routes
- ✅ REGIONAL endpoint configuration
- ✅ X-Ray tracing enabled
- ✅ Stack outputs for API Gateway URL, ID, and Stage
- ✅ Aligned with `rfp-contracts/openapi/api-gateway.yaml` specification

**Parameters Required:**
- Lambda function ARNs for all 10 endpoints
- Environment name
- Bucket prefix

### 3. Created CloudFront Distribution Template ✅

**File:** `cloudformation/services/cloudfront-ui.yaml`

CloudFront distribution with proper Origin Access Identity (OAI) configuration:

**Features:**
- ✅ **Origin Access Identity (OAI)** - Secure S3 bucket access
- ✅ **S3 Bucket Policy** - Grants OAI read/list permissions automatically
- ✅ **SPA Support** - 403/404 errors redirected to index.html
- ✅ **HTTPS Only** - Redirects HTTP to HTTPS
- ✅ **Compression** - Gzip/Brotli compression enabled
- ✅ **Caching** - TTL: 0s min, 1 day default, 1 year max
- ✅ **CloudWatch Alarms** - 4xx and 5xx error rate monitoring
- ✅ **Optional Custom Domain** - ACM certificate and custom domain support
- ✅ **Price Class** - North America and Europe only (cost optimization)

**Outputs:**
- CloudFront distribution ID
- CloudFront domain name (d8bbmb3a6jev2.cloudfront.net format)
- CloudFront URL (https://...)
- OAI ID and S3 Canonical User ID

**Solves Previous Issue:**
- Fixes the "Access Denied" 403 error from missing OAI
- Properly configures S3 bucket policy for CloudFront access
- Eliminates need for public S3 bucket

### 4. Updated Deployment Script ✅

**File:** `scripts/deploy-infra.sh`

Enhanced deployment automation:

**New Features:**
- ✅ **Auto-create S3 bucket** for CloudFormation templates
- ✅ **Template upload** - Syncs all templates to S3 before deployment
- ✅ **Versioning enabled** on templates bucket
- ✅ **Master stack deployment** - Deploys all nested stacks automatically
- ✅ **Parameter handling** - Loads from `parameters-<env>.json`
- ✅ **Interactive prompts** - SAM API key, API Gateway, CloudFront deployment
- ✅ **Proper capabilities** - CAPABILITY_IAM and CAPABILITY_NAMED_IAM
- ✅ **Tagging** - Environment, Project, ManagedBy tags

**Usage:**
```bash
./scripts/deploy-infra.sh dev [templates-bucket] [sam-api-key]
```

**Deployment Flow:**
1. Create/verify S3 bucket for templates
2. Upload all CloudFormation templates to S3
3. Deploy master stack (deploys all nested stacks)
4. Optionally deploy API Gateway stack
5. Optionally deploy CloudFront distribution
6. Publish consolidated outputs

### 5. Updated Output Publishing Script ✅

**File:** `scripts/publish-outputs.sh`

Enhanced to extract outputs from master stack and nested stacks:

**Extracts:**
- Master stack name and region
- API Gateway URL and ID
- CloudFront distribution ID, domain, and URL
- S3 bucket names (data, JSON resources)
- SQS queue URL
- Lambda function ARNs
- KMS key ARN
- SNS topic ARN
- CloudWatch dashboard URL
- All raw outputs from master stack

**Output Format:**
```json
{
  "version": "1.0.0",
  "environment": "dev",
  "timestamp": "2024-11-21T...",
  "infrastructure": { ... },
  "apiGateway": { ... },
  "cloudfront": { ... },
  "s3": { ... },
  "sqs": { ... },
  "lambda": { ... },
  "security": { ... },
  "monitoring": { ... },
  "allOutputs": [ ... ]
}
```

Saved to: `cloudformation/outputs/<environment>.json`

## Technical Architecture

### Nested Stack Deployment

```
master-template.yaml
├── core/
│   ├── main-template.yaml (S3, SQS)
│   └── iam-security-policies-simple.yaml
└── services/
    ├── dynamodb-tables.yaml
    ├── lambda-functions.yaml
    ├── s3-bucket-policies.yaml
    ├── s3-event-notifications.yaml
    ├── eventbridge-rules.yaml
    └── monitoring-alerting.yaml

Standalone stacks (optional):
├── services/api-gateway.yaml
└── services/cloudfront-ui.yaml
```

### API Gateway Integration

```
React UI → API Gateway → Lambda Functions
                ↓
         rfp-contracts/openapi/api-gateway.yaml
                ↓
         JSON Schema validation
```

### CloudFront Architecture

```
User Request → CloudFront Distribution
                    ↓
            Origin Access Identity (OAI)
                    ↓
            S3 Bucket (Private)
                    ↓
            index.html (SPA)
```

## Deployment Readiness

### Prerequisites for Deployment

1. **AWS CLI** configured with credentials
2. **SAM.gov API Key** from https://api.sam.gov/
3. **Lambda functions deployed** (for API Gateway integration)
4. **S3 UI bucket created** (for CloudFront distribution)
5. **jq installed** (for output parsing)

### Deployment Commands

```bash
# Full deployment (interactive)
./scripts/deploy-infra.sh dev

# With parameters
./scripts/deploy-infra.sh dev my-templates-bucket MY_SAM_API_KEY

# Just publish outputs
./scripts/publish-outputs.sh dev

# Deploy CloudFront separately
aws cloudformation deploy \
  --template-file cloudformation/services/cloudfront-ui.yaml \
  --stack-name rfp-dev-cloudfront \
  --parameter-overrides \
      Environment=dev \
      BucketPrefix=dev- \
      UiBucketName=dev-sam-website-dev
```

### Validation Steps

```bash
# Validate templates
aws cloudformation validate-template \
  --template-body file://cloudformation/core/master-template.yaml

# Check stack status
aws cloudformation describe-stacks \
  --stack-name rfp-dev-master \
  --query 'Stacks[0].StackStatus'

# View stack outputs
aws cloudformation describe-stacks \
  --stack-name rfp-dev-master \
  --query 'Stacks[0].Outputs'

# Test API Gateway
curl https://<api-id>.execute-api.us-east-1.amazonaws.com/dev/dashboard/metrics

# Check CloudFront
curl https://<distribution-id>.cloudfront.net/
```

## Breaking Changes

None - this is additive work. Existing templates remain compatible.

## Next Steps (Step 3-5)

### Step 3: Create Service Repositories

1. **rfp-ui Repository**
   - Extract `ui/` directory from monorepo
   - Add CloudFront deployment configuration
   - Reference `rfp-contracts` for API types
   - Set up CI/CD pipeline

2. **rfp-lambdas Repository**
   - Extract `src/lambdas/` and `src/shared/`
   - Add deployment scripts
   - Reference `rfp-contracts` for event schemas
   - Set up CI/CD pipeline

3. **rfp-java-api Repository**
   - Extract `java-api/` directory
   - Add Kubernetes deployment manifests
   - Reference Helm chart from `rfp-infrastructure`
   - Set up CI/CD pipeline

### Step 4: Contract Integration

- Add `rfp-contracts` as git submodule to each service repo
- Implement contract validation in CI/CD pipelines
- Generate TypeScript types from OpenAPI specs for UI
- Generate Python types from event schemas for Lambda functions

### Step 5: End-to-End Testing

- Deploy infrastructure to dev environment
- Deploy all services to dev environment
- Validate cross-service communication
- Test API Gateway → Lambda integration
- Test UI → CloudFront → API Gateway flow
- Validate contract compliance

## Success Metrics

✅ Master template successfully references new directory structure  
✅ API Gateway template created with 10 endpoints and full CORS support  
✅ CloudFront template created with OAI and proper S3 bucket policy  
✅ Deployment script enhanced with template upload and nested stack support  
✅ Output publishing script updated to extract master stack outputs  
✅ All changes committed and pushed to GitHub  

## Resources

- **Master Template:** `cloudformation/core/master-template.yaml`
- **API Gateway:** `cloudformation/services/api-gateway.yaml`
- **CloudFront:** `cloudformation/services/cloudfront-ui.yaml`
- **Deploy Script:** `scripts/deploy-infra.sh`
- **Output Script:** `scripts/publish-outputs.sh`
- **Contracts:** `rfp-contracts/openapi/api-gateway.yaml`

## Rollback Plan

If issues arise:
1. Revert to commit `1d5a0f6` (before Step 2)
2. Use old deployment scripts from monorepo
3. Manually deploy individual stacks instead of master template

## Notes

- API Gateway template requires Lambda function ARNs - deploy Lambda stack first
- CloudFront template requires S3 bucket to exist - create bucket before deployment
- Templates bucket is auto-created with versioning enabled
- All templates support dev, staging, and prod environments via parameters
- CORS headers must still be implemented in Lambda functions (API Gateway handles OPTIONS)
