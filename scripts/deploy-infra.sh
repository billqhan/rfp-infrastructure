#!/bin/bash
set -e

# Deploy infrastructure to AWS
# Usage: ./deploy-infra.sh <environment>

ENVIRONMENT=${1:-dev}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "🚀 Deploying infrastructure for environment: $ENVIRONMENT"

# Deploy CloudFormation stacks
echo "📦 Deploying CloudFormation stacks..."
cd "$REPO_ROOT/cloudformation"

# Deploy core infrastructure first
if [ -f "core/vpc.yaml" ]; then
    aws cloudformation deploy \
        --template-file core/vpc.yaml \
        --stack-name "rfp-$ENVIRONMENT-vpc" \
        --parameter-overrides Environment=$ENVIRONMENT \
        --capabilities CAPABILITY_IAM
fi

# Deploy services
for template in services/*.yaml; do
    if [ -f "$template" ]; then
        stack_name=$(basename "$template" .yaml)
        aws cloudformation deploy \
            --template-file "$template" \
            --stack-name "rfp-$ENVIRONMENT-$stack_name" \
            --parameter-overrides Environment=$ENVIRONMENT \
            --capabilities CAPABILITY_IAM
    fi
done

echo "✅ Infrastructure deployment complete"

# Publish outputs
echo "📝 Publishing stack outputs..."
"$SCRIPT_DIR/publish-outputs.sh" "$ENVIRONMENT"

echo "🎉 Deployment complete for $ENVIRONMENT"
