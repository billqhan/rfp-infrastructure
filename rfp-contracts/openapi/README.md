# OpenAPI Specifications

REST API contracts for RFP Response Platform services.

## Files

- `api-gateway.yaml` - API Gateway Lambda endpoints (workflow, opportunities, reports)
- `java-api.yaml` - Java API endpoints (future)

## Validation

Validate OpenAPI specs using Spectral:

```bash
npm install -g @stoplight/spectral-cli
spectral lint api-gateway.yaml
```

## Code Generation

Generate client SDKs from OpenAPI specs:

```bash
# TypeScript/JavaScript client
npx @openapitools/openapi-generator-cli generate \
  -i api-gateway.yaml \
  -g typescript-axios \
  -o ./generated/typescript

# Python client
npx @openapitools/openapi-generator-cli generate \
  -i api-gateway.yaml \
  -g python \
  -o ./generated/python
```

## Mock Server

Run a mock server for development:

```bash
npm install -g @stoplight/prism-cli
prism mock api-gateway.yaml
```

## Viewing Documentation

View interactive API documentation:

```bash
# Swagger UI
docker run -p 8080:8080 -e SWAGGER_JSON=/spec.yaml -v $(pwd):/spec swaggerapi/swagger-ui

# ReDoc
docker run -p 8080:80 -e SPEC_URL=spec.yaml -v $(pwd):/usr/share/nginx/html/spec.yaml redocly/redoc
```

## Contract Testing

Test your API implementation against the spec:

```bash
npm install -g dredd
dredd api-gateway.yaml https://api.example.com/dev
```
