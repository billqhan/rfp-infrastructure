# CloudFormation Outputs

This directory contains published stack outputs in JSON format.
These files are consumed by downstream service repositories.

**Note:** This directory is gitignored. Outputs are generated during deployment.

## Usage

After running `./scripts/deploy-infra.sh <env>`, outputs are published here as `<env>.json`.

Example structure:
```json
{
  "version": "1.0.0",
  "environment": "dev",
  "apiGatewayUrl": "https://xxx.execute-api.us-east-1.amazonaws.com/dev",
  "javaApiUrl": "http://xxx.elb.amazonaws.com",
  "s3Buckets": {...},
  "cloudfront": {...}
}
```

Downstream services fetch these files during their build/deploy process.
