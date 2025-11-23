# ECS Deployment Support Added ✅

**Date:** November 22, 2025  
**Status:** ECS deployment workflow created alongside existing EKS workflow

## Summary

Added complete ECS (Fargate) deployment support for `rfp-java-api` while keeping the existing EKS (Kubernetes) deployment option. Both workflows can coexist, allowing flexibility in deployment strategy.

## Files Created/Modified

### New Files

1. **`.github/workflows/ci-cd-ecs.yml`** (rfp-java-api)
   - Complete CI/CD pipeline for ECS Fargate deployment
   - Uses same build/test stages as EKS workflow
   - Deploys to separate `development-ecs` and `production-ecs` environments
   - Utilizes AWS ECS Deploy Task Definition action

2. **`task-definition-dev.json`** (rfp-java-api)
   - ECS task definition template for development
   - Fargate configuration: 1 vCPU, 2GB memory
   - Environment variables for dev
   - Health check configuration

3. **`task-definition-prod.json`** (rfp-java-api)
   - ECS task definition template for production
   - Fargate configuration: 2 vCPU, 4GB memory
   - Environment variables for prod
   - Optimized JVM settings

4. **`ECS-SETUP.md`** (rfp-java-api)
   - Complete infrastructure setup guide
   - Step-by-step commands for ECS cluster, IAM roles, ALB
   - GitHub secrets configuration
   - Troubleshooting tips

### Updated Files

1. **`GITHUB-SECRETS-SETUP.md`** (rfp-infrastructure)
   - Added ECS-specific secrets documentation
   - Updated GitHub environments section for both EKS and ECS
   - Updated configuration script for ECS secrets

2. **`CI-CD-PIPELINES-COMPLETE.md`** (rfp-infrastructure)
   - Documented both EKS and ECS deployment options
   - Side-by-side comparison of deployment stages
   - Separate required secrets lists

3. **`.github/workflows/ci-cd.yml`** (rfp-java-api)
   - Fixed image tag format to match docker/metadata-action output
   - Now uses `main-{full-sha}` and `{branch}-{full-sha}` tags

4. **`.github/workflows/ci-cd.yml`** (rfp-lambdas)
   - Fixed matrix to include all actual lambda function directories
   - Added: sam-email-notification, sam-merge-and-archive-result-logs, sam-produce-user-report, sam-produce-web-reports
   - Removed: sam-batch-matching, sam-web-reports (non-existent)

## Deployment Options Now Available

### rfp-java-api

| Feature | EKS (ci-cd.yml) | ECS (ci-cd-ecs.yml) |
|---------|-----------------|---------------------|
| **Orchestrator** | Kubernetes | AWS Fargate |
| **Deployment Tool** | Helm | ECS Task Definition |
| **Environments** | development, production | development-ecs, production-ecs |
| **Scaling** | Kubernetes HPA | ECS Auto Scaling |
| **Configuration** | Helm values | Task definition JSON |
| **Health Checks** | K8s probes | ECS health checks |

## Required Actions

### For ECS Deployment

1. **Infrastructure Setup** (One-time)
   ```bash
   # Follow ECS-SETUP.md guide to create:
   - ECS clusters (dev and prod)
   - IAM roles (execution and task roles)
   - CloudWatch log groups
   - Application Load Balancer (optional)
   - Security groups
   - ECS services
   ```

2. **GitHub Secrets** (rfp-java-api repository)
   ```bash
   # Set these additional secrets:
   gh secret set ECS_CLUSTER_DEV --repo billqhan/rfp-java-api
   gh secret set ECS_CLUSTER_PROD --repo billqhan/rfp-java-api
   gh secret set ECS_SERVICE_DEV --repo billqhan/rfp-java-api
   gh secret set ECS_SERVICE_PROD --repo billqhan/rfp-java-api
   gh secret set ECS_TASK_FAMILY_DEV --repo billqhan/rfp-java-api
   gh secret set ECS_TASK_FAMILY_PROD --repo billqhan/rfp-java-api
   ```

3. **GitHub Environments**
   - Create `development-ecs` environment
   - Create `production-ecs` environment
   - Configure protection rules for production-ecs

4. **Update Task Definitions**
   ```bash
   # Replace YOUR_ACCOUNT_ID with actual AWS account ID
   cd rfp-java-api
   ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
   sed -i '' "s/YOUR_ACCOUNT_ID/$ACCOUNT_ID/g" task-definition-dev.json
   sed -i '' "s/YOUR_ACCOUNT_ID/$ACCOUNT_ID/g" task-definition-prod.json
   ```

5. **Commit and Push Changes**
   ```bash
   cd rfp-java-api
   git add .github/workflows/ci-cd-ecs.yml
   git add task-definition-dev.json
   git add task-definition-prod.json
   git add ECS-SETUP.md
   git commit -m "feat: add ECS deployment workflow alongside EKS"
   git push origin main
   
   # Update rfp-lambdas workflow
   cd ../rfp-lambdas
   git add .github/workflows/ci-cd.yml
   git commit -m "fix(ci): correct lambda matrix to match actual functions"
   git push origin main
   
   # Update infrastructure docs
   cd ../rfp-infrastructure
   git add GITHUB-SECRETS-SETUP.md CI-CD-PIPELINES-COMPLETE.md
   git commit -m "docs: add ECS deployment documentation"
   git push origin main
   ```

### For Fixing Existing Pipeline Failures

1. **rfp-lambdas**: Push the fixed workflow to correct the matrix
2. **rfp-java-api**: Push both workflow fixes (EKS image tags and new ECS workflow)
3. **All repos**: Verify GitHub secrets are set per GITHUB-SECRETS-SETUP.md

## Workflow Triggers

Both workflows trigger on the same events but deploy to different environments:

- **EKS Workflow** (ci-cd.yml)
  - Develop branch → `development` environment on EKS
  - Main branch → `production` environment on EKS

- **ECS Workflow** (ci-cd-ecs.yml)
  - Develop branch → `development-ecs` environment on ECS
  - Main branch → `production-ecs` environment on ECS

## Testing

### Test ECS Deployment

```bash
# 1. Complete ECS infrastructure setup (see ECS-SETUP.md)

# 2. Push to develop branch
git checkout develop
git push origin develop

# 3. Monitor workflow in GitHub Actions

# 4. Check ECS service
aws ecs describe-services \
  --cluster dev-ecs-cluster \
  --services dev-java-api-service

# 5. Test endpoint
curl http://<ALB-DNS>/actuator/health
```

### Test EKS Deployment

```bash
# 1. Ensure EKS cluster exists and GitHub secrets are set

# 2. Push to develop branch
git checkout develop
git push origin develop

# 3. Monitor workflow in GitHub Actions

# 4. Check pods
kubectl get pods -n dev

# 5. Test endpoint
curl http://<service-endpoint>/actuator/health
```

## Migration Strategy

If migrating from EKS to ECS:

1. ✅ Set up ECS infrastructure completely
2. ✅ Deploy to ECS dev environment and test thoroughly
3. ✅ Run parallel deployments to both EKS and ECS for a period
4. ✅ Switch traffic to ECS (update DNS/load balancer)
5. ✅ Monitor ECS deployment performance
6. ✅ Deprecate EKS deployment when stable
7. ✅ Archive or delete EKS workflow

## Cost Comparison

| Resource | EKS | ECS Fargate |
|----------|-----|-------------|
| **Control Plane** | ~$73/month | Free |
| **Worker Nodes** | EC2 costs | Pay per task |
| **Minimum Cost** | Higher (cluster + nodes) | Lower (pay-per-use) |
| **Scaling** | Node-based | Task-based |
| **Best For** | Complex K8s workloads | Simple containerized apps |

## Next Steps

1. Choose deployment target (ECS, EKS, or both)
2. Complete infrastructure setup for chosen target
3. Configure all required GitHub secrets
4. Update task definition templates with real account IDs
5. Commit and push workflow changes
6. Test deployment to dev environment
7. Verify application functionality
8. Deploy to production when ready

## Support

- ECS Setup Guide: `rfp-java-api/ECS-SETUP.md`
- Secrets Configuration: `rfp-infrastructure/GITHUB-SECRETS-SETUP.md`
- Pipeline Documentation: `rfp-infrastructure/CI-CD-PIPELINES-COMPLETE.md`
- AWS ECS Documentation: https://docs.aws.amazon.com/ecs/
- GitHub Actions: https://docs.github.com/en/actions

---

**Note**: Both EKS and ECS workflows are production-ready. Choose based on your operational requirements, cost considerations, and team expertise.
