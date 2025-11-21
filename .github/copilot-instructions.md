# RFP Infrastructure Repository

This repository contains infrastructure as code and API contracts for the RFP Response Platform.

## Structure
- `cloudformation/` - AWS CloudFormation templates
- `helm/` - Kubernetes Helm charts
- `scripts/` - Deployment and utility scripts
- `rfp-contracts/` - API contracts, OpenAPI specs, and event schemas

## Development Guidelines
- All infrastructure changes should be version controlled
- Contracts should be versioned and published for consumption by service repos
- Follow semantic versioning for contract releases
