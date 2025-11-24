# RFP Platform Troubleshooting Guide

This guide documents common issues encountered during deployment and their solutions.

## Table of Contents

1. [ECS Task Failures](#ecs-task-failures)
2. [CloudFront Issues](#cloudfront-issues)
3. [Load Balancer Problems](#load-balancer-problems)
4. [UI Blank Page](#ui-blank-page)
5. [API Connectivity](#api-connectivity)
6. [CloudFormation Stack Failures](#cloudformation-stack-failures)
7. [Docker Build Issues](#docker-build-issues)

---

## ECS Task Failures

### Issue: Tasks stop immediately after starting

**Symptoms:**
```
Task stopped at: 2024-01-15T10:30:00Z
Stop code: TaskFailedToStart
```

**Common Causes:**

#### 1. Architecture Mismatch (ARM64 vs AMD64)

**Error Message:**
```
exec /usr/local/openjdk-17/bin/java: exec format error
```

**Solution:**
Build multi-architecture Docker image:
```bash
cd rfp-java-api
./build.sh --dockerx --skip-tests
```

**How it works:**
- Local Mac uses ARM64 architecture
- ECS Fargate requires AMD64 (X86_64)
- Multi-arch build creates both: `linux/amd64` and `linux/arm64`

**Verification:**
```bash
# Check image architecture
docker buildx imagetools inspect 160936122037.dkr.ecr.us-east-1.amazonaws.com/dev-rfp-java-api:latest

# Should show both architectures:
# - linux/amd64
# - linux/arm64
```

#### 2. Health Check Path Incorrect

**Error Message:**
```
Health check failed with HTTP status 404
```

**Solution:**
Update task definition with correct health check path:
```json
{
  "healthCheck": {
    "command": ["CMD-SHELL", "curl -f http://localhost:8080/api/actuator/health || exit 1"],
    "interval": 30,
    "timeout": 5,
    "retries": 3,
    "startPeriod": 60
  }
}
```

**Why it fails:**
- Spring Boot app uses `/api` context path
- Health check must include context: `/api/actuator/health`
- Not just `/actuator/health`

**Verification:**
```bash
# Inside container:
curl http://localhost:8080/api/actuator/health
# Should return: {"status":"UP"}
```

#### 3. Insufficient Memory

**Error Message:**
```
OutOfMemoryError: Container killed due to memory usage
```

**Solution:**
Increase memory in task definition:
```json
{
  "memory": "2048",  // Increase from 1024 to 2048 MB
  "cpu": "1024"
}
```

### Debugging Commands

```bash
# Check service status
aws ecs describe-services \
  --cluster dev-ecs-cluster \
  --services dev-java-api-service

# Get task details
aws ecs describe-tasks \
  --cluster dev-ecs-cluster \
  --tasks <task-arn>

# View logs
aws logs tail /ecs/dev-java-api --follow

# Use verification script
cd rfp-java-api
./verify-deployment.sh dev
```

---

## CloudFront Issues

### Issue: Nested stack CREATE_FAILED

**Error Message:**
```
CloudFormation nested stack creation failed
Resource: UiStack
Status: CREATE_FAILED
```

**Workaround:**
Use manual deployment script:
```bash
cd rfp-infrastructure/scripts
./deploy-cloudfront-manual.sh
```

**What it does:**
1. Creates S3 bucket separately
2. Creates CloudFront stack with reference to existing bucket
3. Bypasses nested stack complexity

**Files created:**
- S3 bucket: `rfp-han-dev-ui`
- CloudFront distribution: `d3bq9x49ahr8gq.cloudfront.net`

### Issue: Master stack in UPDATE_ROLLBACK_COMPLETE state

**Status:**
```
aws cloudformation describe-stacks --stack-name rfp-dev-master
Status: UPDATE_ROLLBACK_COMPLETE
```

**Impact:**
- Master stack cannot be updated
- Child stacks still functional
- Non-blocking issue

**Options:**

1. **Keep as-is** (recommended):
   - Child stacks work independently
   - CloudFront deployed separately
   - No functional impact

2. **Delete and recreate**:
   ```bash
   # WARNING: Deletes all resources
   aws cloudformation delete-stack --stack-name rfp-dev-master
   
   # Wait for deletion
   aws cloudformation wait stack-delete-complete --stack-name rfp-dev-master
   
   # Redeploy
   ./scripts/deploy-infra.sh dev
   ```

### Issue: CloudFront cache not clearing

**Symptoms:**
- Old content still visible after deployment
- Changes take > 5 minutes to appear

**Solution:**
Create cache invalidation:
```bash
# Get distribution ID
DISTRIBUTION_ID=$(aws cloudfront list-distributions \
  --query "DistributionList.Items[?Comment=='RFP Platform UI - dev'].Id" \
  --output text)

# Create invalidation
aws cloudfront create-invalidation \
  --distribution-id $DISTRIBUTION_ID \
  --paths "/*"

# Check status
aws cloudfront get-invalidation \
  --distribution-id $DISTRIBUTION_ID \
  --id <invalidation-id>
```

**Wait time:** 1-3 minutes for invalidation to complete

---

## Load Balancer Problems

### Issue: ALB targets showing as "unhealthy"

**Symptoms:**
```bash
aws elbv2 describe-target-health --target-group-arn <arn>
# State: unhealthy
# Reason: Target.FailedHealthChecks
```

**Common Causes:**

#### 1. Wrong Health Check Path

**Solution:**
Update target group health check:
```bash
aws elbv2 modify-target-group \
  --target-group-arn <arn> \
  --health-check-path /api/actuator/health \
  --health-check-interval-seconds 30 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 3
```

#### 2. Security Group Misconfiguration

**Solution:**
Ensure security groups allow traffic:

**ALB Security Group:**
```yaml
Ingress:
  - IpProtocol: tcp
    FromPort: 80
    ToPort: 80
    CidrIp: 0.0.0.0/0
  - IpProtocol: tcp
    FromPort: 443
    ToPort: 443
    CidrIp: 0.0.0.0/0
```

**ECS Task Security Group:**
```yaml
Ingress:
  - IpProtocol: tcp
    FromPort: 8080
    ToPort: 8080
    SourceSecurityGroupId: !Ref AlbSecurityGroup
```

**Verification:**
```bash
# Test from ALB security group context
# Get ALB SG ID
ALB_SG=$(aws cloudformation describe-stacks \
  --stack-name rfp-dev-java-api-alb \
  --query 'Stacks[0].Outputs[?OutputKey==`AlbSecurityGroupId`].OutputValue' \
  --output text)

# Get ECS task IP
TASK_IP=$(aws ecs describe-tasks \
  --cluster dev-ecs-cluster \
  --tasks <task-arn> \
  --query 'tasks[0].attachments[0].details[?name==`privateIPv4Address`].value' \
  --output text)

# Test connectivity (from EC2 instance with ALB SG)
curl http://$TASK_IP:8080/api/actuator/health
```

#### 3. Tasks Not Registered with ALB

**Symptoms:**
- Target group shows "unused" state
- No targets listed

**Solution:**
Force new deployment to register tasks:
```bash
aws ecs update-service \
  --cluster dev-ecs-cluster \
  --service dev-java-api-service \
  --force-new-deployment

# Wait for healthy targets (2-3 minutes)
# Use deploy-alb.sh script for automatic retry logic
```

### Debugging Commands

```bash
# Check ALB status
aws elbv2 describe-load-balancers \
  --names dev-java-api-alb

# Check target health
aws elbv2 describe-target-health \
  --target-group-arn <arn>

# Test ALB endpoint
curl http://dev-java-api-alb-189652080.us-east-1.elb.amazonaws.com/api/actuator/health

# Check ALB access logs (if enabled)
aws s3 ls s3://<alb-logs-bucket>/
```

---

## UI Blank Page

### Issue: CloudFront serves blank page

**Symptoms:**
- Browser shows white page
- No JavaScript errors
- Source shows empty `<div id="root"></div>`

**Common Causes:**

#### 1. Missing API Endpoint Configuration

**Check:**
```bash
# Verify .env.production exists
cat rfp-ui/.env.production

# Should contain:
# VITE_API_BASE_URL=http://dev-java-api-alb-189652080.us-east-1.elb.amazonaws.com/api
```

**Solution:**
Deploy UI with correct endpoint:
```bash
cd rfp-ui
./deploy.sh rfp-han-dev-ui
```

The script automatically:
1. Fetches ALB URL from CloudFormation
2. Creates/updates `.env.production`
3. Builds with correct API endpoint
4. Uploads to S3
5. Invalidates CloudFront cache

#### 2. Build Errors Not Caught

**Check:**
```bash
# Build locally and check for errors
cd rfp-ui
npm install
npm run build

# Look for errors in output
```

**Common build errors:**
- Missing environment variables
- TypeScript compilation errors
- Import path issues

#### 3. CloudFront Cache Serving Old Content

**Solution:**
```bash
# Create invalidation
aws cloudfront create-invalidation \
  --distribution-id <id> \
  --paths "/*"

# Wait 1-3 minutes, then refresh browser with Cmd+Shift+R (Mac) or Ctrl+Shift+R (Windows)
```

### Debugging Steps

1. **Check S3 files uploaded:**
   ```bash
   aws s3 ls s3://rfp-han-dev-ui/ --recursive
   # Should show index.html and assets/
   ```

2. **Test S3 file directly:**
   ```bash
   # Get S3 URL from CloudFormation output (if website hosting enabled)
   # Or use CloudFront URL
   curl -I https://d3bq9x49ahr8gq.cloudfront.net/
   # Should return 200 OK
   ```

3. **Check browser console:**
   - Open DevTools (F12)
   - Look for:
     - 404 errors on JavaScript files
     - CORS errors
     - API connection errors

4. **Verify build output:**
   ```bash
   cd rfp-ui/dist
   ls -la
   # Should contain index.html and assets/
   
   # Check index.html references
   cat index.html | grep -o 'src="[^"]*"'
   ```

---

## API Connectivity

### Issue: UI cannot reach Java API

**Symptoms:**
- Browser console shows: `Failed to fetch`
- Network tab shows failed requests to `/api/*`
- CORS errors

**Diagnosis:**

```bash
# 1. Check if ALB is accessible
curl http://dev-java-api-alb-189652080.us-east-1.elb.amazonaws.com/api/actuator/health

# 2. Check UI configuration
cat rfp-ui/.env.production | grep VITE_API_BASE_URL

# 3. Check built files include correct endpoint
cd rfp-ui
grep -r "VITE_API_BASE_URL" dist/ || grep -r "dev-java-api-alb" dist/
```

**Solutions:**

#### 1. ALB Not Deployed

```bash
cd rfp-infrastructure/scripts
./deploy-alb.sh
```

#### 2. UI Using Wrong Endpoint

```bash
# Update and redeploy
cd rfp-ui
./deploy.sh rfp-han-dev-ui
# Script automatically fetches ALB URL
```

#### 3. CORS Not Configured

Add to Java API:
```java
@Configuration
public class WebConfig {
    @Bean
    public WebMvcConfigurer corsConfigurer() {
        return new WebMvcConfigurer() {
            @Override
            public void addCorsMappings(CorsRegistry registry) {
                registry.addMapping("/api/**")
                    .allowedOrigins("https://d3bq9x49ahr8gq.cloudfront.net")
                    .allowedMethods("GET", "POST", "PUT", "DELETE");
            }
        };
    }
}
```

---

## CloudFormation Stack Failures

### Issue: Stack rollback on update/create

**Common Causes:**

#### 1. Parameter Validation Errors

```
Parameter validation failed: Invalid value for parameter
```

**Solution:**
- Check parameter types match template
- Verify required parameters provided
- Ensure constraints met (e.g., min/max values)

#### 2. Resource Limit Exceeded

```
You have exceeded the maximum number of VPCs
```

**Solution:**
```bash
# Check current usage
aws ec2 describe-vpcs

# Delete unused VPCs
aws ec2 delete-vpc --vpc-id vpc-xxxxx
```

#### 3. Resource Already Exists

```
Resource with name already exists
```

**Solution:**
- Use unique names with environment prefix
- Delete conflicting resource manually
- Or reference existing resource instead of creating

### Debugging Commands

```bash
# Get stack events
aws cloudformation describe-stack-events \
  --stack-name rfp-dev-master \
  --max-items 20

# Get specific resource status
aws cloudformation describe-stack-resource \
  --stack-name rfp-dev-master \
  --logical-resource-id EcsCluster

# Validate template before deployment
aws cloudformation validate-template \
  --template-body file://template.yaml
```

---

## Docker Build Issues

### Issue: Build fails with architecture warning

**Error:**
```
WARNING: The requested image's platform (linux/arm64) does not match the detected host platform (linux/amd64)
```

**Solution:**
Use buildx for multi-platform:
```bash
# Enable buildx
docker buildx create --use

# Build multi-arch
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --push \
  -t 160936122037.dkr.ecr.us-east-1.amazonaws.com/dev-rfp-java-api:latest .

# Or use build script
./build.sh --dockerx --skip-tests
```

### Issue: ECR authentication fails

**Error:**
```
denied: User not authenticated to ECR
```

**Solution:**
```bash
# Get ECR login token
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin 160936122037.dkr.ecr.us-east-1.amazonaws.com

# Or use build script (handles auth automatically)
./build.sh --dockerx --skip-tests
```

### Issue: Build context too large

**Error:**
```
Error response from daemon: maximum image size exceeded
```

**Solution:**
Add to `.dockerignore`:
```
node_modules/
target/
dist/
.git/
*.log
*.tmp
```

---

## Quick Reference

### Health Check Endpoints

```bash
# Java API
curl http://dev-java-api-alb-189652080.us-east-1.elb.amazonaws.com/api/actuator/health

# Direct to ECS task (from within VPC)
curl http://<task-private-ip>:8080/api/actuator/health

# CloudFront (UI)
curl -I https://d3bq9x49ahr8gq.cloudfront.net/
```

### Useful AWS CLI Commands

```bash
# ECS
aws ecs list-services --cluster dev-ecs-cluster
aws ecs describe-services --cluster dev-ecs-cluster --services dev-java-api-service
aws ecs list-tasks --cluster dev-ecs-cluster --service-name dev-java-api-service
aws logs tail /ecs/dev-java-api --follow

# CloudFormation
aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE
aws cloudformation describe-stacks --stack-name rfp-dev-java-api-alb
aws cloudformation describe-stack-resources --stack-name rfp-dev-java-api-alb

# ALB/Target Groups
aws elbv2 describe-load-balancers
aws elbv2 describe-target-groups
aws elbv2 describe-target-health --target-group-arn <arn>

# CloudFront
aws cloudfront list-distributions
aws cloudfront get-distribution --id <id>
aws cloudfront create-invalidation --distribution-id <id> --paths "/*"

# S3
aws s3 ls s3://rfp-han-dev-ui/
aws s3 sync dist/ s3://rfp-han-dev-ui/ --delete

# ECR
aws ecr describe-repositories
aws ecr describe-images --repository-name dev-rfp-java-api
docker buildx imagetools inspect 160936122037.dkr.ecr.us-east-1.amazonaws.com/dev-rfp-java-api:latest
```

### Deployment Scripts

```bash
# Complete deployment (all components)
cd rfp-infrastructure/scripts
./deploy-complete.sh dev

# Individual components
./deploy-infra.sh dev              # Core infrastructure
./deploy-cloudfront-manual.sh       # CloudFront CDN
./deploy-alb.sh                     # Application Load Balancer

cd ../rfp-java-api
./build.sh --dockerx --skip-tests   # Multi-arch Docker build
./deploy-ecs.sh dev                 # ECS deployment
./verify-deployment.sh dev          # Verification

cd ../rfp-ui
./deploy.sh rfp-han-dev-ui          # UI deployment

# Selective deployment (skip components)
SKIP_INFRA=true ./deploy-complete.sh dev  # Skip infrastructure
SKIP_ALB=true ./deploy-complete.sh dev    # Skip ALB
```

---

## Getting Help

If you encounter issues not covered in this guide:

1. **Check CloudWatch Logs:**
   ```bash
   aws logs tail /ecs/dev-java-api --follow
   ```

2. **Review CloudFormation Events:**
   ```bash
   aws cloudformation describe-stack-events --stack-name <stack-name>
   ```

3. **Verify AWS Service Limits:**
   - Check service quotas in AWS Console
   - Request limit increases if needed

4. **Test Components Individually:**
   - Deploy one component at a time
   - Verify each before proceeding
   - Use verification scripts

5. **Review Documentation:**
   - `rfp-infrastructure/README.md`
   - `rfp-java-api/QUICKSTART-ECS.md`
   - `rfp-ui/IMPLEMENTATION-SUMMARY.md`
