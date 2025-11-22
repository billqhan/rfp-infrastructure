#!/bin/bash
set -e

# Deploy infrastructure to AWS using nested CloudFormation stacks
# Usage: ./deploy-infra.sh <environment> [templates-bucket] [sam-api-key]
#
# Parameters:
#   environment      - Environment name (dev, staging, prod)
#   templates-bucket - S3 bucket for CloudFormation templates (optional, will create if not provided)
#   sam-api-key      - SAM.gov API key (optional, will prompt if not provided)

ENVIRONMENT=${1:-dev}
TEMPLATES_BUCKET=${2:-""}
SAM_API_KEY=${3:-""}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLOUDFORMATION_DIR="$REPO_ROOT/cloudformation"

echo "🚀 Deploying RFP infrastructure for environment: $ENVIRONMENT"

# Determine bucket name for templates
if [ -z "$TEMPLATES_BUCKET" ]; then
    TEMPLATES_BUCKET="rfp-cloudformation-templates-$ENVIRONMENT-$(aws sts get-caller-identity --query Account --output text)"
    echo "📦 Using templates bucket: $TEMPLATES_BUCKET"
fi

# Create S3 bucket if it doesn't exist
if ! aws s3 ls "s3://$TEMPLATES_BUCKET" 2>&1 | grep -q 'NoSuchBucket'; then
    echo "✅ Templates bucket exists: $TEMPLATES_BUCKET"
else
    echo "📦 Creating templates bucket: $TEMPLATES_BUCKET"
    REGION=$(aws configure get region)
    if [ "$REGION" = "us-east-1" ]; then
        aws s3 mb "s3://$TEMPLATES_BUCKET"
    else
        aws s3 mb "s3://$TEMPLATES_BUCKET" --region "$REGION"
    fi
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "$TEMPLATES_BUCKET" \
        --versioning-configuration Status=Enabled
    
    echo "✅ Templates bucket created"
fi

# Upload all CloudFormation templates to S3
echo "📤 Uploading CloudFormation templates to S3..."
aws s3 sync "$CLOUDFORMATION_DIR/core/" "s3://$TEMPLATES_BUCKET/cloudformation/core/" \
    --exclude "*.md" \
    --exclude "*.json"
aws s3 sync "$CLOUDFORMATION_DIR/services/" "s3://$TEMPLATES_BUCKET/cloudformation/services/" \
    --exclude "*.md"
echo "✅ Templates uploaded"

# Prompt for SAM API key if not provided
if [ -z "$SAM_API_KEY" ]; then
    read -sp "🔑 Enter SAM.gov API key: " SAM_API_KEY
    echo
fi

# Load parameters from parameters file if it exists
PARAMS_FILE="$CLOUDFORMATION_DIR/core/parameters-$ENVIRONMENT.json"
BUCKET_PREFIX=""
COMPANY_NAME="Your Company"
COMPANY_CONTACT="contact@yourcompany.com"
KNOWLEDGE_BASE_ID="PLACEHOLDER"

if [ -f "$PARAMS_FILE" ]; then
    echo "📋 Loading parameters from $PARAMS_FILE"
    BUCKET_PREFIX=$(jq -r '.[] | select(.ParameterKey=="BucketPrefix") | .ParameterValue' "$PARAMS_FILE" || echo "")
    COMPANY_NAME=$(jq -r '.[] | select(.ParameterKey=="CompanyName") | .ParameterValue' "$PARAMS_FILE" || echo "Your Company")
    COMPANY_CONTACT=$(jq -r '.[] | select(.ParameterKey=="CompanyContact") | .ParameterValue' "$PARAMS_FILE" || echo "contact@yourcompany.com")
    KNOWLEDGE_BASE_ID=$(jq -r '.[] | select(.ParameterKey=="KnowledgeBaseId") | .ParameterValue' "$PARAMS_FILE" || echo "PLACEHOLDER")
fi

# Deploy the master template (which deploys all nested stacks)
echo "🏗️  Deploying master CloudFormation stack..."
aws cloudformation deploy \
    --template-file "$CLOUDFORMATION_DIR/core/master-template.yaml" \
    --stack-name "rfp-$ENVIRONMENT-master" \
    --parameter-overrides \
        Environment="$ENVIRONMENT" \
        SamApiKey="$SAM_API_KEY" \
        CompanyName="$COMPANY_NAME" \
        CompanyContact="$COMPANY_CONTACT" \
        TemplatesBucketName="$TEMPLATES_BUCKET" \
        TemplatesBucketPrefix="cloudformation/" \
        BucketPrefix="$BUCKET_PREFIX" \
        KnowledgeBaseId="$KNOWLEDGE_BASE_ID" \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --tags \
        Environment="$ENVIRONMENT" \
        Project="RFP-Response-Platform" \
        ManagedBy="CloudFormation"

echo "✅ Master stack deployment complete"

# Optionally deploy API Gateway stack (if Lambda functions exist)
if [ -f "$CLOUDFORMATION_DIR/services/api-gateway.yaml" ]; then
    echo "🌐 Checking if API Gateway stack should be deployed..."
    echo "⚠️  API Gateway requires Lambda function ARNs from the master stack"
    echo "   Run this after Lambda functions are deployed, or skip for now"
    read -p "Deploy API Gateway? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "🌐 Deploying API Gateway stack..."
        # Note: You'll need to pass Lambda ARNs from the master stack outputs
        echo "ℹ️  Manual deployment required with Lambda ARNs from stack outputs"
    fi
fi

# Optionally deploy CloudFront stack (if UI bucket exists)
if [ -f "$CLOUDFORMATION_DIR/services/cloudfront-ui.yaml" ]; then
    echo "☁️  Checking if CloudFront distribution should be deployed..."
    read -p "Deploy CloudFront for UI? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        UI_BUCKET_NAME="${BUCKET_PREFIX}sam-website-$ENVIRONMENT"
        echo "☁️  Deploying CloudFront distribution for bucket: $UI_BUCKET_NAME"
        aws cloudformation deploy \
            --template-file "$CLOUDFORMATION_DIR/services/cloudfront-ui.yaml" \
            --stack-name "rfp-$ENVIRONMENT-cloudfront" \
            --parameter-overrides \
                Environment="$ENVIRONMENT" \
                BucketPrefix="$BUCKET_PREFIX" \
                UiBucketName="$UI_BUCKET_NAME" \
            --capabilities CAPABILITY_IAM \
            --tags \
                Environment="$ENVIRONMENT" \
                Project="RFP-Response-Platform"
        echo "✅ CloudFront distribution deployed"
    fi
fi

# Publish outputs
echo "📝 Publishing stack outputs..."
"$SCRIPT_DIR/publish-outputs.sh" "$ENVIRONMENT"

echo ""
echo "🎉 Deployment complete for $ENVIRONMENT!"
echo ""
echo "📊 View your stacks:"
echo "   aws cloudformation describe-stacks --stack-name rfp-$ENVIRONMENT-master"
echo ""
echo "📋 Stack outputs saved to: $REPO_ROOT/cloudformation/outputs/$ENVIRONMENT.json"
