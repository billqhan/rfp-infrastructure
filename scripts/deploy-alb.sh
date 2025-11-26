#!/bin/bash

# Deploy Application Load Balancer for Java API ECS Service
# This script creates an ALB to provide a stable endpoint for the Java API

set -e  # Exit on error (will be disabled for optional service update)

ENVIRONMENT=${1:-dev}
REGION="us-east-1"

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
TEMPLATES_BUCKET="rfp-cloudformation-templates-${ENVIRONMENT}-${ACCOUNT_ID}"
STACK_NAME="rfp-${ENVIRONMENT}-java-api-alb"
CLUSTER_NAME="${ENVIRONMENT}-ecs-cluster"
SERVICE_NAME="${ENVIRONMENT}-java-api-service"

log_info "Deploying ALB for Java API ECS Service"
log_info "Environment: $ENVIRONMENT"
log_info "Region: $REGION"
echo ""

# Step 1: Get VPC and Subnets
log_info "Step 1: Getting VPC and subnet information..."
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query 'Vpcs[0].VpcId' --output text --region $REGION)

if [ -z "$VPC_ID" ] || [ "$VPC_ID" = "None" ]; then
    log_error "Could not find default VPC"
    exit 1
fi

# Get at least 2 subnets in different AZs for ALB
SUBNET_IDS=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'Subnets[0:2].SubnetId' \
    --output text \
    --region $REGION | tr '\t' ',')

log_success "VPC ID: $VPC_ID"
log_success "Subnet IDs: $SUBNET_IDS"

# Step 2: Upload template
log_info "Step 2: Uploading CloudFormation template..."
cd "$(dirname "$0")/.."
aws s3 cp cloudformation/services/alb-java-api.yaml \
    s3://${TEMPLATES_BUCKET}/services/alb-java-api.yaml \
    --region $REGION
log_success "Template uploaded"

# Step 3: Check if stack exists
log_info "Step 3: Checking if ALB stack exists..."
if aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region $REGION >/dev/null 2>&1; then
    log_warning "Stack already exists: $STACK_NAME"
    log_info "Updating existing stack..."
    
    aws cloudformation update-stack \
        --stack-name "$STACK_NAME" \
        --template-url "https://${TEMPLATES_BUCKET}.s3.amazonaws.com/services/alb-java-api.yaml" \
        --parameters \
            ParameterKey=Environment,ParameterValue=$ENVIRONMENT \
            ParameterKey=VpcId,ParameterValue=$VPC_ID \
            ParameterKey=SubnetIds,ParameterValue=\"${SUBNET_IDS}\" \
            ParameterKey=EcsClusterName,ParameterValue=$CLUSTER_NAME \
            ParameterKey=EcsServiceName,ParameterValue=$SERVICE_NAME \
            ParameterKey=ContainerName,ParameterValue=java-api \
            ParameterKey=ContainerPort,ParameterValue=8080 \
            ParameterKey=HealthCheckPath,ParameterValue=/api/actuator/health \
        --region $REGION
    
    log_info "Waiting for stack update..."
    aws cloudformation wait stack-update-complete --stack-name "$STACK_NAME" --region $REGION
else
    log_info "Creating new ALB stack..."
    
    aws cloudformation create-stack \
        --stack-name "$STACK_NAME" \
        --template-url "https://${TEMPLATES_BUCKET}.s3.amazonaws.com/services/alb-java-api.yaml" \
        --parameters \
            ParameterKey=Environment,ParameterValue=$ENVIRONMENT \
            ParameterKey=VpcId,ParameterValue=$VPC_ID \
            ParameterKey=SubnetIds,ParameterValue=\"${SUBNET_IDS}\" \
            ParameterKey=EcsClusterName,ParameterValue=$CLUSTER_NAME \
            ParameterKey=EcsServiceName,ParameterValue=$SERVICE_NAME \
            ParameterKey=ContainerName,ParameterValue=java-api \
            ParameterKey=ContainerPort,ParameterValue=8080 \
            ParameterKey=HealthCheckPath,ParameterValue=/api/actuator/health \
        --region $REGION
    
    log_info "Waiting for stack creation (2-3 minutes)..."
    aws cloudformation wait stack-create-complete --stack-name "$STACK_NAME" --region $REGION
fi

log_success "ALB stack deployed"

# Step 4: Get ALB outputs
log_info "Step 4: Retrieving ALB details..."
ALB_URL=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region $REGION \
    --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerUrl`].OutputValue' \
    --output text)

TG_ARN=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region $REGION \
    --query 'Stacks[0].Outputs[?OutputKey==`TargetGroupArn`].OutputValue' \
    --output text)

TASK_SG=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region $REGION \
    --query 'Stacks[0].Outputs[?OutputKey==`EcsTaskSecurityGroupId`].OutputValue' \
    --output text)

log_success "ALB URL: $ALB_URL"
log_success "Target Group ARN: $TG_ARN"
log_success "Task Security Group: $TASK_SG"

# Step 5: Update ECS service to use ALB (if service exists)
# Disable exit-on-error for this section since service may not exist yet
set +e

log_info "Step 5: Checking if ECS service exists..."

# Check if cluster exists first
CLUSTER_EXISTS=$(aws ecs describe-clusters \
    --clusters $CLUSTER_NAME \
    --region $REGION \
    --query 'clusters[0].status' \
    --output text 2>/dev/null)

if [ "$CLUSTER_EXISTS" != "ACTIVE" ]; then
    log_info "ECS cluster does not exist yet. ALB is ready for service creation."
    SERVICE_EXISTS=""
else
    # Check if service exists
    SERVICE_EXISTS=$(aws ecs describe-services \
        --cluster $CLUSTER_NAME \
        --services $SERVICE_NAME \
        --region $REGION \
        --query 'services[0].serviceName' \
        --output text 2>/dev/null)
fi

if [ "$SERVICE_EXISTS" == "$SERVICE_NAME" ]; then
    log_info "Updating ECS service to use ALB..."
    
    # Get current network configuration
    SUBNETS=$(aws ecs describe-services \
        --cluster $CLUSTER_NAME \
        --services $SERVICE_NAME \
        --region $REGION \
        --query 'services[0].networkConfiguration.awsvpcConfiguration.subnets' \
        --output json)

    SUBNETS_LIST=$(echo $SUBNETS | jq -r 'join(",")')

    # Update service with ALB configuration
    aws ecs update-service \
        --cluster $CLUSTER_NAME \
        --service $SERVICE_NAME \
        --load-balancers "targetGroupArn=${TG_ARN},containerName=java-api,containerPort=8080" \
        --health-check-grace-period-seconds 60 \
        --network-configuration "awsvpcConfiguration={subnets=[${SUBNETS_LIST}],securityGroups=[${TASK_SG}],assignPublicIp=ENABLED}" \
        --region $REGION \
        --query 'service.serviceName' \
        --output text >/dev/null

    log_success "ECS service updated"

    # Step 6: Force new deployment to register with ALB
    log_info "Step 6: Forcing new deployment to register tasks..."
    aws ecs update-service \
        --cluster $CLUSTER_NAME \
        --service $SERVICE_NAME \
        --force-new-deployment \
        --region $REGION \
        --query 'service.serviceName' \
        --output text >/dev/null

    log_success "New deployment initiated"

    # Step 7: Wait for targets to become healthy
    log_info "Step 7: Waiting for targets to become healthy (this may take 2-3 minutes)..."
    ATTEMPTS=0
    MAX_ATTEMPTS=20

    while [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
        sleep 15
        ATTEMPTS=$((ATTEMPTS + 1))
        
        HEALTHY_COUNT=$(aws elbv2 describe-target-health \
            --target-group-arn $TG_ARN \
            --region $REGION \
            --query 'length(TargetHealthDescriptions[?TargetHealth.State==`healthy`])' \
            --output text)
        
        if [ "$HEALTHY_COUNT" -gt 0 ]; then
            log_success "Targets are healthy!"
            break
        fi
        
        log_info "Waiting for targets to become healthy... (attempt $ATTEMPTS/$MAX_ATTEMPTS)"
    done

    if [ $ATTEMPTS -eq $MAX_ATTEMPTS ]; then
        log_warning "Targets did not become healthy within expected time"
        log_info "Check target health manually: aws elbv2 describe-target-health --target-group-arn $TG_ARN"
    fi

    # Step 8: Test health endpoint
    log_info "Step 8: Testing health endpoint..."
    sleep 5

    HEALTH_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "${ALB_URL}/api/actuator/health" || echo "000")

    if [ "$HEALTH_RESPONSE" = "200" ]; then
        log_success "Health check passed!"
        curl -s "${ALB_URL}/api/actuator/health" | jq .
    else
        log_warning "Health check returned status: $HEALTH_RESPONSE"
        log_info "The service may still be starting up. Test manually: ${ALB_URL}/api/actuator/health"
    fi
else
    log_info "ECS service does not exist yet. ALB is ready for service creation."
fi

# Re-enable exit-on-error
set -e

echo ""
log_success "ALB deployment complete!"
echo ""
echo "📋 Details:"
echo "   ALB URL:         $ALB_URL"
echo "   Health Check:    ${ALB_URL}/api/actuator/health"
echo "   Target Group:    $TG_ARN"
echo "   Security Group:  $TASK_SG"
echo ""
echo "📦 Next steps:"
echo "   1. Update UI environment: VITE_API_BASE_URL=${ALB_URL}/api"
echo "   2. Redeploy UI with new API endpoint"
echo "   3. Test UI at CloudFront URL"
echo ""
