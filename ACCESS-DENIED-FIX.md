# S3 Access Denied Fix - Resolution Summary

## Issue
After updating CloudFront stack to add ALB origin for API proxy, the UI showed "Access Denied" error when accessed via CloudFront URL.

## Root Cause
CloudFront stack update created a **new Origin Access Identity (OAI)** but the S3 bucket policy still referenced the **old OAI**, causing CloudFront to be denied access to S3 bucket contents.

## Timeline
1. **Initial State**: Working CloudFront distribution with OAI `E1QVNELR53MOAO`
2. **CloudFront Update**: Added ALB origin for API proxy, which created new OAI `E4NBGMUUKQLDX`
3. **Bucket Policy**: Still referenced old OAI `E1QVNELR53MOAO`
4. **Result**: CloudFront couldn't access S3, returned 403 Access Denied

## Solution Applied

### Step 1: Identify Current OAI
```bash
aws cloudfront get-distribution --id E31OSXN880F2UX \
  --query "Distribution.DistributionConfig.Origins.Items[?Id=='S3-UI-Origin'].S3OriginConfig.OriginAccessIdentity" \
  --output text
```
**Result**: `origin-access-identity/cloudfront/E4NBGMUUKQLDX`

### Step 2: Update Bucket Policy
Created new bucket policy with correct OAI:
```json
{
  "Version": "2008-10-17",
  "Statement": [
    {
      "Sid": "CloudFrontOAIReadAccess",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::cloudfront:user/CloudFront Origin Access Identity E4NBGMUUKQLDX"
      },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::rfp-han-dev-ui/*"
    },
    {
      "Sid": "CloudFrontOAIListAccess",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::cloudfront:user/CloudFront Origin Access Identity E4NBGMUUKQLDX"
      },
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::rfp-han-dev-ui"
    }
  ]
}
```

### Step 3: Apply Policy
```bash
aws s3api put-bucket-policy \
  --bucket rfp-han-dev-ui \
  --policy file:///tmp/bucket-policy.json
```

## Verification

### UI Access Test
```bash
curl -s -o /dev/null -w "%{http_code}" https://d3bq9x49ahr8gq.cloudfront.net/
```
**Result**: `200` ✅

### API Proxy Test
```bash
curl -s https://d3bq9x49ahr8gq.cloudfront.net/api/actuator/health
```
**Result**: `{"status":"UP"}` ✅

## Current Configuration

- **CloudFront Distribution**: E31OSXN880F2UX
- **CloudFront URL**: https://d3bq9x49ahr8gq.cloudfront.net
- **S3 Bucket**: rfp-han-dev-ui
- **Origin Access Identity**: E4NBGMUUKQLDX
- **UI Origin**: rfp-han-dev-ui.s3.us-east-1.amazonaws.com
- **API Origin**: dev-java-api-alb-189652080.us-east-1.elb.amazonaws.com

## Routing
- `/` → S3 (UI static files)
- `/api/*` → ALB (Java API backend)

## Security
- S3 bucket is **private** (no public access)
- Access only via CloudFront using OAI
- All traffic uses **HTTPS** (mixed content issue resolved)

## Prevention for Future Deployments

**Note**: When updating CloudFront stack or creating new OAI, always update S3 bucket policy:

```bash
# 1. Get OAI ID from CloudFront
OAI_ID=$(aws cloudfront get-distribution --id DISTRIBUTION_ID \
  --query "Distribution.DistributionConfig.Origins.Items[?Id=='S3-UI-Origin'].S3OriginConfig.OriginAccessIdentity" \
  --output text | cut -d'/' -f4)

# 2. Update bucket policy with new OAI
cat > /tmp/bucket-policy.json <<EOF
{
  "Version": "2008-10-17",
  "Statement": [
    {
      "Sid": "CloudFrontOAIReadAccess",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::cloudfront:user/CloudFront Origin Access Identity $OAI_ID"
      },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::BUCKET_NAME/*"
    },
    {
      "Sid": "CloudFrontOAIListAccess",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::cloudfront:user/CloudFront Origin Access Identity $OAI_ID"
      },
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::BUCKET_NAME"
    }
  ]
}
EOF

aws s3api put-bucket-policy --bucket BUCKET_NAME --policy file:///tmp/bucket-policy.json
```

## Status
✅ **RESOLVED** - UI and API both accessible via HTTPS through CloudFront

## Related Issues Fixed
1. **Mixed Content Error**: Resolved by adding ALB as CloudFront origin for API proxy
2. **Access Denied**: Resolved by updating S3 bucket policy with correct OAI

## Date
December 2024
