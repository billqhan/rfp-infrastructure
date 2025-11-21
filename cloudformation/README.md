# CloudFormation Templates

AWS infrastructure definitions for the RFP Response Platform.

## Structure

- `core/` - Core infrastructure (VPC, IAM, networking)
- `services/` - Service-specific stacks (API Gateway, ECS, Lambda, S3, CloudFront)
- `outputs/` - Published stack outputs (gitignored)

## Deployment

Deploy all stacks:
```bash
../scripts/deploy-infra.sh dev
```

Deploy individual stack:
```bash
aws cloudformation deploy \
  --template-file services/api-gateway.yaml \
  --stack-name rfp-dev-api-gateway \
  --parameter-overrides Environment=dev \
  --capabilities CAPABILITY_IAM
```

## Stack Dependencies

1. `core/vpc.yaml` - VPC, subnets, security groups
2. `core/iam.yaml` - IAM roles and policies
3. `services/s3.yaml` - S3 buckets
4. `services/api-gateway.yaml` - API Gateway + Lambda backend
5. `services/ecs.yaml` - ECS cluster + Java API service
6. `services/cloudfront.yaml` - CloudFront distribution

## Outputs

After deployment, run `../scripts/publish-outputs.sh <env>` to generate `outputs/<env>.json` for downstream services.
