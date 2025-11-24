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
aws s3 sync "$CLOUDFORMATION_DIR/" "s3://$TEMPLATES_BUCKET/" \
    --exclude "*.md" \
    --exclude ".DS_Store" \
    --delete
echo "✅ Templates uploaded"

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
    
    # Load SAM API key from params if not provided via command line
    if [ -z "$SAM_API_KEY" ]; then
        SAM_API_KEY=$(jq -r '.[] | select(.ParameterKey=="SamApiKey") | .ParameterValue' "$PARAMS_FILE" || echo "")
    fi
fi

# Prompt for SAM API key if still not provided
if [ -z "$SAM_API_KEY" ] || [ "$SAM_API_KEY" = "YOUR_SAM_API_KEY_HERE" ]; then
    read -sp "🔑 Enter SAM.gov API key: " SAM_API_KEY
    echo
fi

# Check if stack exists
STACK_NAME="rfp-$ENVIRONMENT-master"
if aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region us-east-1 >/dev/null 2>&1; then
    echo "🔄 Updating existing CloudFormation stack..."
    aws cloudformation update-stack \
        --stack-name "$STACK_NAME" \
        --template-url "https://$TEMPLATES_BUCKET.s3.amazonaws.com/core/master-template.yaml" \
        --parameters file://"$PARAMS_FILE" \
        --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
        --region us-east-1
    
    echo "⏳ Waiting for stack update to complete..."
    aws cloudformation wait stack-update-complete --stack-name "$STACK_NAME" --region us-east-1
else
    echo "🏗️  Creating new CloudFormation stack..."
    aws cloudformation create-stack \
        --stack-name "$STACK_NAME" \
        --template-url "https://$TEMPLATES_BUCKET.s3.amazonaws.com/core/master-template.yaml" \
        --parameters file://"$PARAMS_FILE" \
        --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
        --tags \
            Key=Environment,Value="$ENVIRONMENT" \
            Key=Project,Value="RFP-Response-Platform" \
            Key=ManagedBy,Value="CloudFormation" \
        --region us-east-1
    
    echo "⏳ Waiting for stack creation to complete..."
    aws cloudformation wait stack-create-complete --stack-name "$STACK_NAME" --region us-east-1
fi

echo "✅ Master stack deployment complete"

# Publish outputs
echo "📝 Publishing stack outputs..."
"$SCRIPT_DIR/publish-outputs.sh" "$ENVIRONMENT"

# Display CloudFront URL if available
echo ""
echo "🎉 Deployment complete for $ENVIRONMENT!"
echo ""
CLOUDFRONT_URL=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region us-east-1 \
    --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontDistributionUrl`].OutputValue' \
    --output text 2>/dev/null || echo "")

if [ -n "$CLOUDFRONT_URL" ]; then
    echo "🌐 CloudFront UI URL: $CLOUDFRONT_URL"
    
    CLOUDFRONT_ID=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region us-east-1 \
        --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontDistributionId`].OutputValue' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$CLOUDFRONT_ID" ]; then
        echo "📋 CloudFront Distribution ID: $CLOUDFRONT_ID"
    fi
fi

echo ""
echo "📊 View your stacks:"
echo "   aws cloudformation describe-stacks --stack-name $STACK_NAME"
echo ""
echo "📋 Stack outputs saved to: $REPO_ROOT/cloudformation/outputs/$ENVIRONMENT.json"
