# RFP Contracts

API contracts, OpenAPI specifications, and event schemas for the RFP Response Platform.

## Overview

This directory contains the source of truth for all inter-service communication contracts:
- REST API specifications (OpenAPI 3.0)
- Event schemas (JSON Schema for SQS, SNS, EventBridge)
- Shared data models

## Structure

```
rfp-contracts/
├── openapi/              # REST API specifications
│   ├── api-gateway.yaml # API Gateway endpoints
│   ├── java-api.yaml    # Java API endpoints
│   └── README.md        # OpenAPI documentation
├── events/              # Event schemas
│   ├── workflow/        # Workflow event schemas
│   ├── notifications/   # Notification event schemas
│   └── README.md        # Event schema documentation
└── README.md            # This file
```

## Versioning

Contracts follow semantic versioning (MAJOR.MINOR.PATCH):
- **MAJOR**: Breaking changes (incompatible API changes)
- **MINOR**: New features (backward-compatible)
- **PATCH**: Bug fixes (backward-compatible)

Current version: `1.0.0`

## Using Contracts

### In Service Repositories

Services should consume contracts as a dependency:

**Option 1: Git Submodule**
```bash
git submodule add <repo-url> contracts
```

**Option 2: Direct Copy (with version pinning)**
```bash
# In your service repo
curl -o contracts/api-gateway.yaml https://raw.githubusercontent.com/org/rfp-infrastructure/v1.0.0/rfp-contracts/openapi/api-gateway.yaml
```

**Option 3: NPM Package (for JavaScript/TypeScript)**
Publish contracts as an npm package and install:
```bash
npm install @rfp/contracts@1.0.0
```

### Contract Testing

Each service should run contract tests in CI to ensure compliance:
- OpenAPI validation (schema, paths, responses)
- Event schema validation (JSON Schema)
- Mock server tests against OpenAPI spec

## Contributing

1. Create a feature branch from `main`
2. Update relevant OpenAPI specs or event schemas
3. Increment version number appropriately
4. Run validation: `npm run validate` or `make validate`
5. Submit PR with description of changes
6. After merge, tag release with new version

## Contract Change Process

### Breaking Changes (MAJOR version bump)
- Notify all consuming services
- Provide migration guide
- Coordinate deployment across services
- Tag new major version after all services updated

### Non-Breaking Changes (MINOR/PATCH)
- Can be deployed independently
- Services can upgrade at their own pace
- Tag release immediately after merge

## Validation

Run contract validation locally:

```bash
# Validate OpenAPI specs
npm run validate:openapi

# Validate event schemas
npm run validate:events

# Validate all
npm run validate
```

## Example: Consuming API Gateway Contract

```javascript
// In rfp-ui or rfp-lambdas
import spec from '@rfp/contracts/openapi/api-gateway.yaml';

// Use for mock server, validation, or code generation
const mockServer = new MockServer(spec);
```

## Tools

Recommended tools for working with contracts:
- **OpenAPI**: Swagger Editor, Redoc, Spectral (linting)
- **JSON Schema**: ajv (validation), quicktype (code generation)
- **Testing**: Prism (mock server), Dredd (contract testing)

## Links

- OpenAPI Spec: [openapi/](openapi/)
- Event Schemas: [events/](events/)
- Contract Tests: (in individual service repos)
