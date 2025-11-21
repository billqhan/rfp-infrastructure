# Event Schemas

JSON Schema definitions for asynchronous events in the RFP Response Platform.

## Schemas

- `workflow-event.schema.json` - Workflow state change events (SQS, EventBridge)
- `notification-event.schema.json` - Notification events (SNS)

## Event Flow

```
EventBridge (Schedule) → Download Lambda → SQS → Process Lambda → SQS → Match Lambda
                                                                           ↓
                                                                    SNS (Notifications)
```

## Validation

Validate event payloads using ajv:

```bash
npm install -g ajv-cli
ajv validate -s workflow-event.schema.json -d sample-event.json
```

## Example Event

```json
{
  "eventId": "550e8400-e29b-41d4-a716-446655440000",
  "eventType": "workflow.step.completed",
  "timestamp": "2025-11-21T10:30:00Z",
  "workflowId": "wf-20251121-001",
  "step": "match",
  "status": "completed",
  "metadata": {
    "opportunitiesProcessed": 150,
    "matchesFound": 42,
    "duration": 45.3
  },
  "triggeredBy": "schedule"
}
```

## Consuming Events

### In Lambda Functions (Python)

```python
import json
import jsonschema

# Load schema
with open('workflow-event.schema.json') as f:
    schema = json.load(f)

def lambda_handler(event, context):
    # Validate incoming event
    try:
        jsonschema.validate(instance=event, schema=schema)
    except jsonschema.ValidationError as e:
        return {'statusCode': 400, 'body': f'Invalid event: {e}'}
    
    # Process valid event
    workflow_id = event['workflowId']
    step = event['step']
    # ...
```

### In Java API

```java
import com.fasterxml.jackson.databind.JsonNode;
import com.networknt.schema.JsonSchema;
import com.networknt.schema.JsonSchemaFactory;

// Load schema
InputStream schemaStream = getClass().getResourceAsStream("/workflow-event.schema.json");
JsonSchema schema = JsonSchemaFactory.getInstance().getSchema(schemaStream);

// Validate event
Set<ValidationMessage> errors = schema.validate(eventJson);
if (!errors.isEmpty()) {
    throw new ValidationException("Invalid event: " + errors);
}
```

## Testing

Test event producers and consumers:

```bash
# Mock event producer
aws sqs send-message \
  --queue-url https://sqs.us-east-1.amazonaws.com/.../workflow-queue \
  --message-body file://sample-event.json

# Mock event consumer (validate and process)
python validate_event.py < sample-event.json
```
