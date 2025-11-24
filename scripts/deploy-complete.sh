#!/bin/bash

# Complete RFP Platform Deployment Script
# This script orchestrates the full deployment workflow:
# 1. Infrastructure (VPC, ECS, RDS)
# 2. CloudFront CDN
# 3. Application Load Balancer
# 4. Java API (Docker build + ECS deploy)
# 5. Lambda Functions
# 6. UI (Build + S3/CloudFront deploy)

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENVIRONMENT="${1:-dev}"
SKIP_INFRA="${SKIP_INFRA:-false}"
SKIP_ALB="${SKIP_ALB:-false}"
SKIP_JAVA="${SKIP_JAVA:-false}"
SKIP_LAMBDA="${SKIP_LAMBDA:-false}"
SKIP_UI="${SKIP_UI:-false}"

echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}║                                                       ║${NC}"
echo -e "${CYAN}║    RFP PLATFORM COMPLETE DEPLOYMENT                   ║${NC}"
echo -e "${CYAN}║                                                       ║${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${BLUE}Environment:${NC} $ENVIRONMENT"
echo -e "${BLUE}Timestamp:${NC} $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Load environment configuration
if [ -f "$SCRIPT_DIR/../../.env.${ENVIRONMENT}" ]; then
    source "$SCRIPT_DIR/../../.env.${ENVIRONMENT}"
    echo -e "${GREEN}✅ Loaded environment configuration${NC}"
else
    echo -e "${YELLOW}⚠️  No .env.${ENVIRONMENT} file found, using defaults${NC}"
fi

# Verify AWS credentials
echo ""
echo -e "${YELLOW}Verifying AWS credentials...${NC}"
if ! AWS_IDENTITY=$(aws sts get-caller-identity 2>/dev/null); then
    echo -e "${RED}❌ AWS credentials not configured${NC}"
    echo -e "${YELLOW}ℹ️  Configure credentials:${NC}"
    echo "   aws configure"
    exit 1
fi
AWS_ACCOUNT=$(echo "$AWS_IDENTITY" | jq -r '.Account')
AWS_USER=$(echo "$AWS_IDENTITY" | jq -r '.Arn' | cut -d'/' -f2)
echo -e "${GREEN}✅ AWS Account: $AWS_ACCOUNT${NC}"
echo -e "${GREEN}✅ AWS User: $AWS_USER${NC}"

# ===========================================================================
# STEP 1: Infrastructure Deployment
# ===========================================================================
if [ "$SKIP_INFRA" != "true" ]; then
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}STEP 1: INFRASTRUCTURE DEPLOYMENT${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo ""
    
    if [ -f "$SCRIPT_DIR/deploy-infra.sh" ]; then
        echo -e "${BLUE}Deploying core infrastructure...${NC}"
        bash "$SCRIPT_DIR/deploy-infra.sh" "$ENVIRONMENT"
        echo -e "${GREEN}✅ Infrastructure deployment completed${NC}"
    else
        echo -e "${YELLOW}⚠️  deploy-infra.sh not found, skipping${NC}"
    fi
    
    # Deploy CloudFront (may need manual script if master stack has issues)
    echo ""
    echo -e "${BLUE}Deploying CloudFront CDN...${NC}"
    if [ -f "$SCRIPT_DIR/deploy-cloudfront-manual.sh" ]; then
        bash "$SCRIPT_DIR/deploy-cloudfront-manual.sh"
        echo -e "${GREEN}✅ CloudFront deployment completed${NC}"
    else
        echo -e "${YELLOW}⚠️  CloudFront already deployed or script not found${NC}"
    fi
else
    echo -e "${YELLOW}⏭️  Skipping infrastructure deployment (SKIP_INFRA=true)${NC}"
fi

# ===========================================================================
# STEP 2: Application Load Balancer
# ===========================================================================
if [ "$SKIP_ALB" != "true" ]; then
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}STEP 2: APPLICATION LOAD BALANCER${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo ""
    
    if [ -f "$SCRIPT_DIR/deploy-alb.sh" ]; then
        echo -e "${BLUE}Deploying ALB for Java API...${NC}"
        bash "$SCRIPT_DIR/deploy-alb.sh"
        echo -e "${GREEN}✅ ALB deployment completed${NC}"
    else
        echo -e "${RED}❌ deploy-alb.sh not found${NC}"
        echo -e "${YELLOW}ℹ️  ALB is required for Java API routing${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}⏭️  Skipping ALB deployment (SKIP_ALB=true)${NC}"
fi

# ===========================================================================
# STEP 3: Java API Deployment
# ===========================================================================
if [ "$SKIP_JAVA" != "true" ]; then
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}STEP 3: JAVA API DEPLOYMENT${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo ""
    
    JAVA_DIR="$SCRIPT_DIR/../../rfp-java-api"
    if [ -d "$JAVA_DIR" ]; then
        cd "$JAVA_DIR"
        
        # Build multi-arch Docker image
        echo -e "${BLUE}Building multi-arch Docker image...${NC}"
        if [ -f "build.sh" ]; then
            bash build.sh --dockerx --skip-tests
            echo -e "${GREEN}✅ Docker image built${NC}"
        else
            echo -e "${RED}❌ build.sh not found${NC}"
            exit 1
        fi
        
        # Deploy to ECS
        echo ""
        echo -e "${BLUE}Deploying to ECS...${NC}"
        if [ -f "deploy-ecs.sh" ]; then
            bash deploy-ecs.sh "$ENVIRONMENT"
            echo -e "${GREEN}✅ ECS deployment completed${NC}"
        else
            echo -e "${RED}❌ deploy-ecs.sh not found${NC}"
            exit 1
        fi
        
        # Verify deployment
        echo ""
        echo -e "${BLUE}Verifying deployment...${NC}"
        if [ -f "verify-deployment.sh" ]; then
            bash verify-deployment.sh "$ENVIRONMENT"
            echo -e "${GREEN}✅ Deployment verified${NC}"
        else
            echo -e "${YELLOW}⚠️  verify-deployment.sh not found, skipping verification${NC}"
        fi
        
        cd "$SCRIPT_DIR"
    else
        echo -e "${RED}❌ Java API directory not found: $JAVA_DIR${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}⏭️  Skipping Java API deployment (SKIP_JAVA=true)${NC}"
fi

# ===========================================================================
# STEP 4: Lambda Functions Deployment
# ===========================================================================
if [ "$SKIP_LAMBDA" != "true" ]; then
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}STEP 4: LAMBDA FUNCTIONS DEPLOYMENT${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo ""
    
    LAMBDA_DIR="$SCRIPT_DIR/../../rfp-lambdas"
    if [ -d "$LAMBDA_DIR" ]; then
        cd "$LAMBDA_DIR"
        
        if [ -f "scripts/deploy-all.sh" ]; then
            echo -e "${BLUE}Deploying Lambda functions...${NC}"
            bash scripts/deploy-all.sh
            echo -e "${GREEN}✅ Lambda deployment completed${NC}"
        else
            echo -e "${YELLOW}⚠️  scripts/deploy-all.sh not found, skipping${NC}"
        fi
        
        cd "$SCRIPT_DIR"
    else
        echo -e "${YELLOW}⚠️  Lambda directory not found, skipping${NC}"
    fi
else
    echo -e "${YELLOW}⏭️  Skipping Lambda deployment (SKIP_LAMBDA=true)${NC}"
fi

# ===========================================================================
# STEP 5: UI Deployment
# ===========================================================================
if [ "$SKIP_UI" != "true" ]; then
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}STEP 5: UI DEPLOYMENT${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo ""
    
    UI_DIR="$SCRIPT_DIR/../../rfp-ui"
    if [ -d "$UI_DIR" ]; then
        cd "$UI_DIR"
        
        if [ -f "deploy.sh" ]; then
            # Get bucket name from CloudFormation
            BUCKET_NAME=$(aws cloudformation describe-stacks \
                --stack-name "rfp-${ENVIRONMENT}-cloudfront" \
                --query 'Stacks[0].Outputs[?OutputKey==`S3BucketName`].OutputValue' \
                --output text 2>/dev/null || echo "")
            
            if [ -z "$BUCKET_NAME" ] || [ "$BUCKET_NAME" == "None" ]; then
                BUCKET_NAME="rfp-han-${ENVIRONMENT}-ui"
                echo -e "${YELLOW}⚠️  Using default bucket name: $BUCKET_NAME${NC}"
            fi
            
            echo -e "${BLUE}Deploying UI to S3/CloudFront...${NC}"
            bash deploy.sh "$BUCKET_NAME"
            echo -e "${GREEN}✅ UI deployment completed${NC}"
        else
            echo -e "${RED}❌ deploy.sh not found${NC}"
            exit 1
        fi
        
        cd "$SCRIPT_DIR"
    else
        echo -e "${RED}❌ UI directory not found: $UI_DIR${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}⏭️  Skipping UI deployment (SKIP_UI=true)${NC}"
fi

# ===========================================================================
# DEPLOYMENT SUMMARY
# ===========================================================================
echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}║                                                       ║${NC}"
echo -e "${CYAN}║    DEPLOYMENT COMPLETE!                               ║${NC}"
echo -e "${CYAN}║                                                       ║${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
echo ""

# Get deployment URLs
echo -e "${GREEN}🌐 DEPLOYMENT URLS:${NC}"
echo ""

# CloudFront URL
CLOUDFRONT_URL=$(aws cloudformation describe-stacks \
    --stack-name "rfp-${ENVIRONMENT}-cloudfront" \
    --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontUrl`].OutputValue' \
    --output text 2>/dev/null || echo "")
if [ -n "$CLOUDFRONT_URL" ] && [ "$CLOUDFRONT_URL" != "None" ]; then
    echo -e "${BLUE}📱 UI (CloudFront):${NC} $CLOUDFRONT_URL"
fi

# ALB URL
ALB_URL=$(aws cloudformation describe-stacks \
    --stack-name "rfp-${ENVIRONMENT}-java-api-alb" \
    --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerUrl`].OutputValue' \
    --output text 2>/dev/null || echo "")
if [ -n "$ALB_URL" ] && [ "$ALB_URL" != "None" ]; then
    echo -e "${BLUE}🔗 Java API (ALB):${NC} $ALB_URL/api"
fi

echo ""
echo -e "${GREEN}📋 VERIFICATION STEPS:${NC}"
echo ""
echo "1. Test UI in browser (wait 1-3 min for CloudFront cache):"
echo -e "   ${CLOUDFRONT_URL}"
echo ""
echo "2. Verify API health:"
echo -e "   curl ${ALB_URL}/api/actuator/health"
echo ""
echo "3. Check ECS service status:"
echo "   aws ecs describe-services --cluster ${ENVIRONMENT}-ecs-cluster --services ${ENVIRONMENT}-java-api-service"
echo ""
echo "4. Monitor CloudFront metrics:"
echo "   aws cloudfront get-distribution-config --id <distribution-id>"
echo ""
echo "5. View application logs:"
echo "   aws logs tail /ecs/${ENVIRONMENT}-java-api --follow"
echo ""

echo -e "${YELLOW}⚠️  TROUBLESHOOTING:${NC}"
echo ""
echo "If any component fails:"
echo "  • Check CloudFormation console for stack events"
echo "  • Review CloudWatch logs for errors"
echo "  • Verify security groups allow required traffic"
echo "  • Ensure ECS tasks are healthy and registered with ALB"
echo "  • Confirm CloudFront cache is cleared (wait 1-3 minutes)"
echo ""
echo "For detailed troubleshooting, see:"
echo "  • rfp-infrastructure/README.md"
echo "  • rfp-java-api/QUICKSTART-ECS.md"
echo "  • rfp-ui/IMPLEMENTATION-SUMMARY.md"
echo ""

echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
echo ""
