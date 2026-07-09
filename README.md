# Hellnet Schema

Centralized schema registry management for event-driven .NET services.

```
Issue (issuer) → Webhook → Schema versioned in repo → Apicurio Registry
```

## How it works

1. **Dev opens an Issue** using the "New Schema" template
2. **GitHub Action** captures the issue, generates the schema file, commits and tags
3. **On merge** to `main`, schema is registered in Apicurio Registry automatically
4. **Hellnet.Kafka** consumes the schema from Registry to serialize/deserialize messages

## Quick Start

### Creating a new schema

Open a new issue and fill the [template](.github/ISSUE_TEMPLATE/new-schema.yml):

```yaml
# What you fill in the issue:
Schema name: hellnet-order-created
Format: avro
Compatibility: BACKWARD
Fields:
  - name: orderId
    type: string
    required: true
  - name: amount
    type: double
    required: true
  - name: currency
    type: string
    default: "BRL"
```

After submitting:

1. Webhook triggers → schema is generated and committed
2. Tag created: `schema/hellnet-order-created/v1`
3. Issue is closed with reference to the schema file
4. PR is created automatically (or you create one to review)
5. On merge to `main`, schema is registered in Apicurio

### Schema storage structure

```
schemas/
├── avro/
│   └── {schema-name}/
│       ├── v1/
│       │   ├── schema.avsc          ← Avro schema
│       │   └── .meta.json           ← Metadata (version, compatibility)
│       └── v2/                      ← Next version
│           ├── schema.avsc
│           └── .meta.json
├── json/
│   └── {schema-name}/
│       └── v1/
│           ├── schema.json
│           └── .meta.json
└── protobuf/
    └── {schema-name}/
        └── v1/
            ├── schema.proto
            └── .meta.json
```

### Example schemas

| Schema | Format | File |
|--------|--------|------|
| Order Created | Avro | `schemas/avro/hellnet-order-created/v1/schema.avsc` |
| Invoice Event | JSON | `schemas/json/hellnet-invoice-event/v1/schema.json` |
| Stock Updated | Protobuf | `schemas/protobuf/hellnet-stock-updated/v1/schema.proto` |

## Schema naming convention

```
hellnet-{domain}-{event}
```

Examples: `hellnet-order-created`, `hellnet-invoice-paid`, `hellnet-stock-updated`

## Git tags

Each schema version creates a tag:

```
schema/hellnet-order-created/v1
schema/hellnet-invoice-event/v2
schema/hellnet-stock-updated/v1
```

## CI/CD Pipeline

| Workflow | Trigger | Action |
|----------|---------|--------|
| `issue-schema.yml` | Issue opened with `schema` label | Generates schema file, commits, tags |
| `validate-pr.yml` | PR with changes in `schemas/` | Validates syntax of all schemas |
| `register-apicurio.yml` | Push to `main` with schema changes | Registers schema in Apicurio Registry |

## Configuration

### Apicurio Registry

Set the following secrets in your GitHub repository:

| Secret | Default | Description |
|--------|---------|-------------|
| `APICURIO_URL` | `http://192.168.1.254:8085` | Apicurio Registry endpoint |

### Compatibility levels

| Level | Description |
|-------|-------------|
| `BACKWARD` | New schema can read data written with the previous |
| `FORWARD` | Old schema can read data written with the new |
| `FULL` | Both backward and forward compatible |
| `NONE` | No compatibility checks |

## Local development

### Validate schemas locally

```bash
./scripts/validate.sh
```

### Register schema manually

```bash
./scripts/register.sh \
  --registry http://192.168.1.254:8085 \
  --group default \
  --schema schemas/avro/hellnet-order-created/v1
```

## Related repos

| Repo | Purpose |
|------|---------|
| `hellnet-dep-kafka` | Kafka pub/sub library (consumes schemas) |
| `hellnet-dep-observability` | OpenTelemetry + logging |
