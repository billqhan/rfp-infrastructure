#!/bin/bash

# Manual CloudFront Deployment Script
# Use this if the master stack CloudFront deployment fails
# This script creates the UI bucket and CloudFront distribution separately

set -e

ENVIRONMENT=${1:-dev}
BUCKET_PREFIX=${2:-rfp-han}

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="us-east-1"
UI_BUCKET_NAME="${BUCKET_PREFIX}-${ENVIRONMENT}-ui"
TEMPLATES_BUCKET="rfp-cloudformation-templates-${ENVIRONMENT}-${ACCOUNT_ID}"
CLOUDFRONT_STACK_NAME="${BUCKET_PREFIX}-${ENVIRONMENT}-cloudfront-ui"

log_info "Manual CloudFront Deployment for $ENVIRONMENT"
log_info "UI Bucket: $UI_BUCKET_NAME"
log_info "Templates Bucket: $TEMPLATES_BUCKET"
log_info "Stack Name: $CLOUDFRONT_STACK_NAME"
echo ""

# Step 1: Create UI bucket
log_info "Step 1: Creating UI bucket..."
if aws s3 ls "s3://$UI_BUCKET_NAME" 2>&1 | grep -q 'NoSuchBucket'; then
    aws s3 mb "s3://$UI_BUCKET_NAME" --region "$REGION"
    log_success "UI bucket created: $UI_BUCKET_NAME"
else
    log_warning "UI bucket already exists: $UI_BUCKET_NAME"
fi

# Step 2: Configure bucket encryption
log_info "Step 2: Configuring bucket encryption..."
aws s3api put-bucket-encryption \
    --bucket "$UI_BUCKET_NAME" \
    --server-side-encryption-configuration '{
        "Rules": [{
            "ApplyServerSideEncryptionByDefault": {
                "SSEAlgorithm": "AES256"
            },
            "BucketKeyEnabled": true
        }]
    }'
log_success "Bucket encryption enabled"

# Step 3: Configure public access block
log_info "Step 3: Configuring public access settings for CloudFront..."
aws s3api put-public-access-block \
    --bucket "$UI_BUCKET_NAME" \
    --public-access-block-configuration \
        "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=false,RestrictPublicBuckets=false"
log_success "Public access configured (allows CloudFront OAI)"

# Step 4: Check if CloudFormation templates are uploaded
log_info "Step 4: Verifying CloudFormation templates..."
if ! aws s3 ls "s3://$TEMPLATES_BUCKET/services/cloudfront-ui.yaml" >/dev/null 2>&1; then
    log_error "CloudFront template not found in S3"
    log_info "Run: cd ../.. && ./scripts/deploy-infra.sh $ENVIRONMENT"
    exit 1
fi
log_success "Templates verified"

# Step 5: Get ALB DNS name
log_info "Step 5: Getting ALB DNS name..."
ALB_STACK_NAME="rfp-${ENVIRONMENT}-java-api-alb"
ALB_DNS_NAME=$(aws cloudformation describe-stacks \
    --stack-name "$ALB_STACK_NAME" \
    --region "$REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerDnsName`].OutputValue' \
    --output text 2>/dev/null || echo "")

if [ -z "$ALB_DNS_NAME" ]; then
    log_error "ALB DNS name not found. Deploy ALB first:"
    log_info "cd ../.. && ./scripts/deploy-alb.sh"
    exit 1
fi
log_success "ALB DNS: $ALB_DNS_NAME"

# Step 6: Create CloudFront stack
log_info "Step 6: Creating CloudFront stack with API proxy..."
if aws cloudformation describe-stacks --stack-name "$CLOUDFRONT_STACK_NAME" --region "$REGION" >/dev/null 2>&1; then
    log_warning "CloudFront stack already exists: $CLOUDFRONT_STACK_NAME"
    log_info "Updating stack..."
    aws cloudformation update-stack \
        --stack-name "$CLOUDFRONT_STACK_NAME" \
        --template-url "https://${TEMPLATES_BUCKET}.s3.amazonaws.com/services/cloudfront-ui.yaml" \
        --parameters \
            "ParameterKey=Environment,ParameterValue=$ENVIRONMENT" \
            "ParameterKey=BucketPrefix,ParameterValue=$BUCKET_PREFIX" \
            "ParameterKey=UiBucketName,ParameterValue=$UI_BUCKET_NAME" \
            "ParameterKey=AlbDnsName,ParameterValue=$ALB_DNS_NAME" \
        --region "$REGION"
    
    log_info "Waiting for stack update (10-15 minutes)..."
    aws cloudformation wait stack-update-complete \
        --stack-name "$CLOUDFRONT_STACK_NAME" \
        --region "$REGION"
else
    aws cloudformation create-stack \
        --stack-name "$CLOUDFRONT_STACK_NAME" \
        --template-url "https://${TEMPLATES_BUCKET}.s3.amazonaws.com/services/cloudfront-ui.yaml" \
        --parameters \
            "ParameterKey=Environment,ParameterValue=$ENVIRONMENT" \
            "ParameterKey=BucketPrefix,ParameterValue=$BUCKET_PREFIX" \
            "ParameterKey=UiBucketName,ParameterValue=$UI_BUCKET_NAME" \
            "ParameterKey=AlbDnsName,ParameterValue=$ALB_DNS_NAME" \
            "ParameterKey=UiBucketName,ParameterValue=$UI_BUCKET_NAME" \
        --tags \
            "Key=Environment,Value=$ENVIRONMENT" \
            "Key=Project,Value=RFP-Response-Platform" \
        --region "$REGION"
    
    log_info "Waiting for stack creation (10-15 minutes)..."
    aws cloudformation wait stack-create-complete \
        --stack-name "$CLOUDFRONT_STACK_NAME" \
        --region "$REGION"
fi

log_success "CloudFront stack deployed successfully"

# Step 6: Get CloudFront details
log_info "Step 6: Retrieving CloudFront details..."
CLOUDFRONT_URL=$(aws cloudformation describe-stacks \
    --stack-name "$CLOUDFRONT_STACK_NAME" \
    --region "$REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontDistributionUrl`].OutputValue' \
    --output text)

CLOUDFRONT_ID=$(aws cloudformation describe-stacks \
    --stack-name "$CLOUDFRONT_STACK_NAME" \
    --region "$REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontDistributionId`].OutputValue' \
    --output text)

echo ""
log_success "CloudFront deployment complete!"
echo ""
echo "📋 Details:"
echo "   UI Bucket:       $UI_BUCKET_NAME"
echo "   CloudFront URL:  $CLOUDFRONT_URL"
echo "   Distribution ID: $CLOUDFRONT_ID"
echo "   Stack Name:      $CLOUDFRONT_STACK_NAME"
echo ""
echo "📦 Next steps:"
echo "   1. Deploy UI: cd ../../rfp-ui && ./deploy.sh $UI_BUCKET_NAME"
echo "   2. Access UI:  $CLOUDFRONT_URL"
echo ""
