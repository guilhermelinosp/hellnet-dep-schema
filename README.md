# Hellnet Schema

Centralized schema registry management for event-driven .NET services.

```
Issue (issuer) → Webhook → Schema versioned in repo → Apicurio Registry
```

## How it works

```
Dev ──abre issue──► Issue Template ──webhook──► Gera schema ──PR──► Review ──merge──► Apicurio Registry
                        ▲                                                        │
                        └────────────────── git tag ─────────────────────────────┘
```

### Fluxo via Issue (webhook)

1. Dev abre issue com template "New Schema"
2. GitHub Action `process-schema-issue` captura (`issues: opened`)
3. Script `generate-from-issue.sh` gera o schema no formato escolhido
4. Action cria branch, commita o schema, e abre um **Pull Request**
5. Time revisa o PR (diff do schema)
6. Ao merge na `main`, workflow `register-apicurio`:
   - Valida compatibilidade com versão anterior
   - Registra no Apicurio Registry
   - Cria tag `schema/{nome}/v{versao}`

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

Non-Fast schemas use the existing generic convention:

```
hellnet-{domain}-{event}
```

Examples: `hellnet-order-created`, `hellnet-invoice-paid`, `hellnet-stock-updated`

Fast Avro schemas use the event contract convention below. The domain is the
first segment after `fast-`; the event is the remaining hyphen-separated text.

```
schema name: fast-{domain}-{event}
namespace:   fast.events.{domain}.v{version}
record name: {EventName}V{version}
```

For example, `fast-ride-requested` v1 uses namespace
`fast.events.ride.v1` and record name `RideRequestedV1`.

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

### GitHub Secrets (obrigatórios)

| Secret | Descrição |
|--------|-----------|
| `APICURIO_URL` | Apicurio Registry endpoint (ex: `http://192.168.1.254:8085`) |
| `APICURIO_TOKEN` | Token de autenticação (se exigido) |

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
  --registry "\$APICURIO_URL" \
  --group default \
  --schema schemas/avro/hellnet-order-created/v1
```

### Redpanda Schema Registry

The repository contains contracts, not event payloads. This script registers Avro
schemas only; it never publishes fake messages. Topic creation is opt-in and does
not publish events.

Prerequisites: `python3` and `curl`. `rpk` is optional and is used only with
`--apply --create-topics`.

```bash
# Safe default: no network writes (REDPANDA_SCHEMA_REGISTRY_URL defaults to
# http://localhost:8081; REDPANDA_BROKERS defaults to localhost:9092).
bash scripts/register-redpanda.sh --dry-run

# Register schemas (does not create topics or publish messages).
bash scripts/register-redpanda.sh --apply --registry http://localhost:8081

# Register and, only when rpk is installed, create the derived topics.
bash scripts/register-redpanda.sh --apply --create-topics
```

The endpoint is the Confluent-compatible Redpanda API:
`POST /subjects/{subject}/versions`, with content type
`application/vnd.schemaregistry.v1+json` and a JSON body whose `schema` value is
the complete Avro document. The stable mapping intentionally keeps subjects and
topics distinct:

| Schema directory | Subject | Topic |
|---|---|---|
| `fast-ride-requested/v1` | `fast-ride-requested` | `ride.requested.v1` |
| `fast-ride-accepted/v1` | `fast-ride-accepted` | `ride.accepted.v1` |

Only directories matching `fast-{domain}-{event}` are accepted. Event names may
contain additional hyphen-separated words, which become dot-separated topic
segments. A dry-run prints the schema, subject, endpoint, and topic without a
write. Registration is idempotent: submitting the same schema to the same
subject lets the registry deduplicate it. Schema Registry synchronization is
separate from publishing events; applications publish real payloads later using
the registered contracts.

## Related repos

| Repo | Purpose |
|------|---------|
| `hellnet-dep-kafka` | Kafka pub/sub library (consumes schemas) |
| `hellnet-dep-observability` | OpenTelemetry + logging |
