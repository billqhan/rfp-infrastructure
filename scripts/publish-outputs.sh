#!/bin/bash
set -e

# Publish CloudFormation stack outputs for downstream services
# Usage: ./publish-outputs.sh <environment>

ENVIRONMENT=${1:-dev}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$(cd "$SCRIPT_DIR/../cloudformation/outputs" && pwd)"
OUTPUT_FILE="$OUTPUT_DIR/$ENVIRONMENT.json"

echo "📝 Publishing outputs for environment: $ENVIRONMENT"

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Query CloudFormation stacks and extract outputs
cat > "$OUTPUT_FILE" <<EOF
{
  "version": "1.0.0",
  "environment": "$ENVIRONMENT",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "apiGatewayUrl": "$(aws cloudformation describe-stacks --stack-name "rfp-$ENVIRONMENT-api-gateway" --query 'Stacks[0].Outputs[?OutputKey==`ApiUrl`].OutputValue' --output text 2>/dev/null || echo '')",
  "javaApiUrl": "$(aws cloudformation describe-stacks --stack-name "rfp-$ENVIRONMENT-java-api" --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerUrl`].OutputValue' --output text 2>/dev/null || echo '')",
  "s3Buckets": {
    "ui": "$(aws cloudformation describe-stacks --stack-name "rfp-$ENVIRONMENT-s3" --query 'Stacks[0].Outputs[?OutputKey==`UiBucket`].OutputValue' --output text 2>/dev/null || echo '')",
    "data": "$(aws cloudformation describe-stacks --stack-name "rfp-$ENVIRONMENT-s3" --query 'Stacks[0].Outputs[?OutputKey==`DataBucket`].OutputValue' --output text 2>/dev/null || echo '')"
  },
  "cloudfront": {
    "distributionId": "$(aws cloudformation describe-stacks --stack-name "rfp-$ENVIRONMENT-cloudfront" --query 'Stacks[0].Outputs[?OutputKey==`DistributionId`].OutputValue' --output text 2>/dev/null || echo '')",
    "domain": "$(aws cloudformation describe-stacks --stack-name "rfp-$ENVIRONMENT-cloudfront" --query 'Stacks[0].Outputs[?OutputKey==`DomainName`].OutputValue' --output text 2>/dev/null || echo '')"
  }
}
EOF

echo "✅ Outputs published to: $OUTPUT_FILE"
cat "$OUTPUT_FILE"

echo ""
echo "📦 To use these outputs in downstream services:"
echo "   - Copy this file to your service repo"
echo "   - Or fetch via: curl <artifact-url>/$ENVIRONMENT.json"
echo "   - Or use AWS SSM Parameter Store to share values"
