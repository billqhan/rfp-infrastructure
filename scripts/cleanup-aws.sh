#!/bin/bash

# Cleanup Script for RFP Platform AWS Deployment
# This script will delete ALL deployed AWS resources

set -e

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

REGION="us-east-1"

echo ""
log_warning "⚠️  WARNING: This will DELETE all deployed AWS resources!"
echo ""
echo "Resources to be deleted:"
echo "  - S3 Buckets: rfp-cloudformation-templates-dev-*, rfp-han-dev-ui"
echo "  - ECR Repository: dev-rfp-java-api"
echo "  - ECS Task Definitions: dev-java-api-task, java-api-task"
echo "  - ECS Clusters (if any)"
echo "  - CloudFormation Stacks (if any)"
echo "  - Lambda Functions (if any)"
echo "  - CloudFront Distributions (if any)"
echo ""
read -p "Are you ABSOLUTELY sure you want to delete everything? (type 'DELETE' to confirm): " CONFIRM

if [ "$CONFIRM" != "DELETE" ]; then
    log_info "Cleanup cancelled."
    exit 0
fi

# Delete S3 Buckets (with proper versioning cleanup)
log_info "Deleting S3 buckets..."

for bucket in $(aws s3 ls | grep -E "rfp|sam|dev" | awk '{print $3}'); do
    log_warning "Deleting bucket: $bucket"
    
    # Check if versioning is enabled
    VERSIONING=$(aws s3api get-bucket-versioning --bucket $bucket --query 'Status' --output text 2>/dev/null || echo "")
    
    if [ "$VERSIONING" = "Enabled" ]; then
        log_info "Removing all versions from $bucket..."
        
        # Delete all versions
        aws s3api list-object-versions --bucket $bucket --output json 2>/dev/null | \
            jq -r '.Versions[]? | "\(.Key) \(.VersionId)"' | \
            while read key version; do
                aws s3api delete-object --bucket $bucket --key "$key" --version-id "$version" 2>/dev/null
            done
        
        # Delete all delete markers
        aws s3api list-object-versions --bucket $bucket --output json 2>/dev/null | \
            jq -r '.DeleteMarkers[]? | "\(.Key) \(.VersionId)"' | \
            while read key version; do
                aws s3api delete-object --bucket $bucket --key "$key" --version-id "$version" 2>/dev/null
            done
    fi
    
    # Empty and delete bucket
    aws s3 rm s3://$bucket --recursive 2>/dev/null || true
    aws s3 rb s3://$bucket --force 2>/dev/null || log_error "Failed to delete $bucket (may need manual cleanup)"
done

# Delete ECR Repository
log_info "Deleting ECR repositories..."

for repo in $(aws ecr describe-repositories --region $REGION --query 'repositories[?contains(repositoryName, `rfp`) || contains(repositoryName, `java`)].repositoryName' --output text 2>/dev/null); do
    log_warning "Deleting ECR repo: $repo"
    aws ecr delete-repository --repository-name $repo --region $REGION --force 2>/dev/null || log_error "Failed to delete $repo"
done

# Delete ECS Services
log_info "Deleting ECS services..."

for cluster in $(aws ecs list-clusters --region $REGION --query 'clusterArns[*]' --output text 2>/dev/null); do
    cluster_name=$(echo $cluster | awk -F'/' '{print $NF}')
    log_info "Checking cluster: $cluster_name"
    
    for service in $(aws ecs list-services --cluster $cluster_name --region $REGION --query 'serviceArns[*]' --output text 2>/dev/null); do
        service_name=$(echo $service | awk -F'/' '{print $NF}')
        log_warning "Deleting service: $service_name"
        aws ecs update-service --cluster $cluster_name --service $service_name --desired-count 0 --region $REGION 2>/dev/null
        aws ecs delete-service --cluster $cluster_name --service $service_name --region $REGION --force 2>/dev/null || log_error "Failed to delete service $service_name"
    done
done

# Delete ECS Clusters
log_info "Deleting ECS clusters..."

for cluster in $(aws ecs list-clusters --region $REGION --query 'clusterArns[*]' --output text 2>/dev/null); do
    cluster_name=$(echo $cluster | awk -F'/' '{print $NF}')
    if echo "$cluster_name" | grep -iq "rfp\|dev\|java"; then
        log_warning "Deleting cluster: $cluster_name"
        aws ecs delete-cluster --cluster $cluster_name --region $REGION 2>/dev/null || log_error "Failed to delete cluster $cluster_name"
    fi
done

# Deregister ECS Task Definitions
log_info "Deregistering ECS task definitions..."

for task_def in $(aws ecs list-task-definitions --region $REGION --query 'taskDefinitionArns[?contains(@, `rfp`) || contains(@, `java`) || contains(@, `dev`)]' --output text 2>/dev/null); do
    log_warning "Deregistering: $task_def"
    aws ecs deregister-task-definition --task-definition $task_def --region $REGION 2>/dev/null || log_error "Failed to deregister $task_def"
done

# Delete Lambda Functions
log_info "Deleting Lambda functions..."

for func in $(aws lambda list-functions --region $REGION --query 'Functions[?contains(FunctionName, `rfp`) || contains(FunctionName, `sam`) || contains(FunctionName, `dev`)].FunctionName' --output text 2>/dev/null); do
    log_warning "Deleting function: $func"
    aws lambda delete-function --function-name $func --region $REGION 2>/dev/null || log_error "Failed to delete $func"
done

# Delete Application Load Balancers (must be done before deleting CloudFormation stacks with dependencies)
log_info "Deleting Application Load Balancers..."

for alb_arn in $(aws elbv2 describe-load-balancers --region $REGION --query 'LoadBalancers[?contains(LoadBalancerName, `dev`) || contains(LoadBalancerName, `rfp`) || contains(LoadBalancerName, `java-api`)].LoadBalancerArn' --output text 2>/dev/null); do
    alb_name=$(aws elbv2 describe-load-balancers --load-balancer-arns $alb_arn --query 'LoadBalancers[0].LoadBalancerName' --output text 2>/dev/null)
    log_warning "Deleting ALB: $alb_name"
    aws elbv2 delete-load-balancer --load-balancer-arn $alb_arn --region $REGION 2>/dev/null || log_error "Failed to delete ALB $alb_name"
done

# Delete Target Groups
log_info "Deleting Target Groups..."

for tg_arn in $(aws elbv2 describe-target-groups --region $REGION --query 'TargetGroups[?contains(TargetGroupName, `dev`) || contains(TargetGroupName, `rfp`) || contains(TargetGroupName, `java-api`)].TargetGroupArn' --output text 2>/dev/null); do
    tg_name=$(aws elbv2 describe-target-groups --target-group-arns $tg_arn --query 'TargetGroups[0].TargetGroupName' --output text 2>/dev/null)
    log_warning "Deleting Target Group: $tg_name"
    aws elbv2 delete-target-group --target-group-arn $tg_arn --region $REGION 2>/dev/null || log_error "Failed to delete TG $tg_name (may need to wait for ALB deletion)"
done

log_info "Waiting 30 seconds for ALB deletion to propagate..."
sleep 30

# Delete CloudFormation Stacks (child stacks first, then master)
log_info "Deleting CloudFormation stacks..."

# First delete ALB stack specifically
for stack in $(aws cloudformation list-stacks --region $REGION --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE --query 'StackSummaries[?contains(StackName, `java-api-alb`)].StackName' --output text 2>/dev/null); do
    log_warning "Deleting ALB stack: $stack"
    aws cloudformation delete-stack --stack-name $stack --region $REGION 2>/dev/null || log_error "Failed to delete stack $stack"
done

log_info "Waiting 30 seconds for ALB stack deletion..."
sleep 30

# Then delete master stack (which will cascade delete nested stacks)
for stack in $(aws cloudformation list-stacks --region $REGION --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE --query 'StackSummaries[?contains(StackName, `rfp`) && !contains(StackName, `alb`)].StackName' --output text 2>/dev/null); do
    # Only delete root stacks, not nested ones (they'll be deleted by parent)
    if ! echo "$stack" | grep -q "Stack-"; then
        log_warning "Deleting stack: $stack"
        aws cloudformation delete-stack --stack-name $stack --region $REGION 2>/dev/null || log_error "Failed to delete stack $stack"
    fi
done

log_info "Waiting for stack deletions to complete (this may take 2-5 minutes)..."
for stack in $(aws cloudformation list-stacks --region $REGION --stack-status-filter DELETE_IN_PROGRESS --query 'StackSummaries[?contains(StackName, `rfp`)].StackName' --output text 2>/dev/null); do
    log_info "Waiting for $stack to delete..."
    aws cloudformation wait stack-delete-complete --stack-name $stack --region $REGION 2>/dev/null || log_warning "Stack $stack may have dependencies"
done

# Delete CloudFront Distributions
log_info "Checking CloudFront distributions..."

for dist_id in $(aws cloudfront list-distributions --query 'DistributionList.Items[?contains(Comment, `rfp`) || contains(Comment, `dev`) || contains(Comment, `han`)].Id' --output text 2>/dev/null); do
    log_warning "Processing distribution: $dist_id"
    
    # Get current config and check if already disabled
    DIST_STATUS=$(aws cloudfront get-distribution --id $dist_id --query 'Distribution.DistributionConfig.Enabled' --output text 2>/dev/null)
    
    if [ "$DIST_STATUS" = "True" ]; then
        log_warning "Disabling distribution: $dist_id"
        
        # Get current config
        ETAG=$(aws cloudfront get-distribution-config --id $dist_id --query 'ETag' --output text 2>/dev/null)
        
        # Disable distribution first
        aws cloudfront get-distribution-config --id $dist_id 2>/dev/null | \
            jq '.DistributionConfig | .Enabled = false' > /tmp/dist-config-$dist_id.json
        
        aws cloudfront update-distribution --id $dist_id --if-match $ETAG --distribution-config file:///tmp/dist-config-$dist_id.json 2>/dev/null || \
            log_error "Failed to disable distribution $dist_id"
        
        log_info "Distribution $dist_id disabled. Will need 15-20 min to fully disable before deletion."
    else
        log_info "Distribution $dist_id already disabled, attempting deletion..."
        
        # Try to delete if fully deployed
        ETAG=$(aws cloudfront get-distribution --id $dist_id --query 'ETag' --output text 2>/dev/null)
        aws cloudfront delete-distribution --id $dist_id --if-match $ETAG 2>/dev/null && \
            log_info "Distribution $dist_id deleted" || \
            log_warning "Distribution $dist_id not yet ready for deletion (may need to wait)"
    fi
done

log_info "Note: CloudFront distributions take 15-20 minutes to fully disable before they can be deleted."
log_info "If distributions still exist, run this script again in 20 minutes."

# Delete CloudWatch Log Groups
log_info "Deleting CloudWatch log groups..."

for log_group in $(aws logs describe-log-groups --region $REGION --query 'logGroups[?contains(logGroupName, `/ecs/`) || contains(logGroupName, `rfp`)].logGroupName' --output text 2>/dev/null); do
    log_warning "Deleting log group: $log_group"
    aws logs delete-log-group --log-group-name $log_group --region $REGION 2>/dev/null || log_error "Failed to delete $log_group"
done

# Delete Security Groups (be careful with default SG)
log_info "Deleting security groups..."

for sg in $(aws ec2 describe-security-groups --region $REGION --query 'SecurityGroups[?contains(GroupName, `java-api`) || contains(GroupName, `rfp`) || contains(GroupName, `ecs`)].GroupId' --output text 2>/dev/null); do
    log_warning "Deleting security group: $sg"
    aws ec2 delete-security-group --group-id $sg --region $REGION 2>/dev/null || log_error "Failed to delete SG $sg (may be in use)"
done

# Delete IAM Roles
log_info "Deleting IAM roles..."

for role in ecsTaskExecutionRole ecsTaskRole; do
    log_warning "Detaching policies from role: $role"
    
    # Detach all policies
    for policy_arn in $(aws iam list-attached-role-policies --role-name $role --query 'AttachedPolicies[*].PolicyArn' --output text 2>/dev/null); do
        aws iam detach-role-policy --role-name $role --policy-arn $policy_arn 2>/dev/null
    done
    
    log_warning "Deleting role: $role"
    aws iam delete-role --role-name $role 2>/dev/null || log_error "Failed to delete role $role"
done

echo ""
log_info "✅ Cleanup complete!"
echo ""
log_warning "Note: CloudFront distributions must be fully disabled before deletion."
log_warning "Check AWS Console in a few minutes and delete them manually if needed."
echo ""
log_info "Verify cleanup:"
echo "  S3 Buckets:          aws s3 ls | grep rfp"
echo "  ECS Clusters:        aws ecs list-clusters --region us-east-1"
echo "  ECR Repositories:    aws ecr describe-repositories --region us-east-1"
echo "  Lambda Functions:    aws lambda list-functions --region us-east-1 --query 'Functions[?contains(FunctionName, \`rfp\`)].FunctionName'"
echo "  CloudFormation:      aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE --query 'StackSummaries[?contains(StackName, \`rfp\`)].StackName'"
echo "  Load Balancers:      aws elbv2 describe-load-balancers --query 'LoadBalancers[?contains(LoadBalancerName, \`dev\`)].LoadBalancerName'"
echo "  Target Groups:       aws elbv2 describe-target-groups --query 'TargetGroups[?contains(TargetGroupName, \`dev\`)].TargetGroupName'"
echo ""
