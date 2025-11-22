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

# Query master stack and nested stack outputs
MASTER_STACK="rfp-$ENVIRONMENT-master"

# Get all outputs from the master stack
MASTER_OUTPUTS=$(aws cloudformation describe-stacks --stack-name "$MASTER_STACK" --query 'Stacks[0].Outputs' --output json 2>/dev/null || echo '[]')

# Get API Gateway outputs if stack exists
API_GATEWAY_URL=""
API_GATEWAY_ID=""
if aws cloudformation describe-stacks --stack-name "rfp-$ENVIRONMENT-api-gateway" &>/dev/null; then
    API_GATEWAY_URL=$(aws cloudformation describe-stacks --stack-name "rfp-$ENVIRONMENT-api-gateway" --query 'Stacks[0].Outputs[?OutputKey==`ApiGatewayUrl`].OutputValue' --output text 2>/dev/null || echo '')
    API_GATEWAY_ID=$(aws cloudformation describe-stacks --stack-name "rfp-$ENVIRONMENT-api-gateway" --query 'Stacks[0].Outputs[?OutputKey==`ApiGatewayId`].OutputValue' --output text 2>/dev/null || echo '')
fi

# Get CloudFront outputs if stack exists
CLOUDFRONT_ID=""
CLOUDFRONT_DOMAIN=""
CLOUDFRONT_URL=""
if aws cloudformation describe-stacks --stack-name "rfp-$ENVIRONMENT-cloudfront" &>/dev/null; then
    CLOUDFRONT_ID=$(aws cloudformation describe-stacks --stack-name "rfp-$ENVIRONMENT-cloudfront" --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontDistributionId`].OutputValue' --output text 2>/dev/null || echo '')
    CLOUDFRONT_DOMAIN=$(aws cloudformation describe-stacks --stack-name "rfp-$ENVIRONMENT-cloudfront" --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontDistributionDomainName`].OutputValue' --output text 2>/dev/null || echo '')
    CLOUDFRONT_URL=$(aws cloudformation describe-stacks --stack-name "rfp-$ENVIRONMENT-cloudfront" --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontDistributionUrl`].OutputValue' --output text 2>/dev/null || echo '')
fi

# Extract key values from master stack outputs
S3_DATA_BUCKET=$(echo "$MASTER_OUTPUTS" | jq -r '.[] | select(.OutputKey=="SamDataInBucketName") | .OutputValue' 2>/dev/null || echo '')
S3_JSON_BUCKET=$(echo "$MASTER_OUTPUTS" | jq -r '.[] | select(.OutputKey=="SamExtractedJsonResourcesBucketName") | .OutputValue' 2>/dev/null || echo '')
SQS_QUEUE_URL=$(echo "$MASTER_OUTPUTS" | jq -r '.[] | select(.OutputKey=="SqsSamJsonMessagesQueueUrl") | .OutputValue' 2>/dev/null || echo '')
LAMBDA_DOWNLOAD_ARN=$(echo "$MASTER_OUTPUTS" | jq -r '.[] | select(.OutputKey=="SamGovDailyDownloadFunctionArn") | .OutputValue' 2>/dev/null || echo '')
LAMBDA_PROCESSOR_ARN=$(echo "$MASTER_OUTPUTS" | jq -r '.[] | select(.OutputKey=="SamJsonProcessorFunctionArn") | .OutputValue' 2>/dev/null || echo '')
KMS_KEY_ARN=$(echo "$MASTER_OUTPUTS" | jq -r '.[] | select(.OutputKey=="SamProcessingKMSKeyArn") | .OutputValue' 2>/dev/null || echo '')
SNS_TOPIC_ARN=$(echo "$MASTER_OUTPUTS" | jq -r '.[] | select(.OutputKey=="SamAlertsTopicArn") | .OutputValue' 2>/dev/null || echo '')
DASHBOARD_URL=$(echo "$MASTER_OUTPUTS" | jq -r '.[] | select(.OutputKey=="SamProcessingDashboardUrl") | .OutputValue' 2>/dev/null || echo '')

# Create consolidated output file
cat > "$OUTPUT_FILE" <<EOF
{
  "version": "1.0.0",
  "environment": "$ENVIRONMENT",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "infrastructure": {
    "masterStack": "$MASTER_STACK",
    "region": "$(aws configure get region)"
  },
  "apiGateway": {
    "url": "$API_GATEWAY_URL",
    "id": "$API_GATEWAY_ID"
  },
  "cloudfront": {
    "distributionId": "$CLOUDFRONT_ID",
    "domain": "$CLOUDFRONT_DOMAIN",
    "url": "$CLOUDFRONT_URL"
  },
  "s3": {
    "dataBucket": "$S3_DATA_BUCKET",
    "jsonResourcesBucket": "$S3_JSON_BUCKET"
  },
  "sqs": {
    "jsonMessagesQueueUrl": "$SQS_QUEUE_URL"
  },
  "lambda": {
    "samGovDailyDownloadArn": "$LAMBDA_DOWNLOAD_ARN",
    "samJsonProcessorArn": "$LAMBDA_PROCESSOR_ARN"
  },
  "security": {
    "kmsKeyArn": "$KMS_KEY_ARN"
  },
  "monitoring": {
    "snsTopicArn": "$SNS_TOPIC_ARN",
    "dashboardUrl": "$DASHBOARD_URL"
  },
  "allOutputs": $MASTER_OUTPUTS
}
EOF

echo "✅ Outputs published to: $OUTPUT_FILE"
cat "$OUTPUT_FILE"

echo ""
echo "📦 To use these outputs in downstream services:"
echo "   - Copy this file to your service repo"
echo "   - Or fetch via: curl <artifact-url>/$ENVIRONMENT.json"
echo "   - Or use AWS SSM Parameter Store to share values"
