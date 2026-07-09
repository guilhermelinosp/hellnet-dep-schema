#!/usr/bin/env bash
# Validate all schemas in the repository.
# Usage: ./validate.sh [schemas/root/dir]
set -euo pipefail

SCHEMAS_DIR="${1:-schemas}"
HAS_ERROR=false

validate_avro() {
  local file="$1"
  python3 -c "
import json, sys
try:
    schema = json.load(open('$file'))
    assert schema.get('type') == 'record'
    assert 'fields' in schema
    name = schema.get('name', 'unknown')
    count = len(schema['fields'])
    print(f'  OK: {name} ({count} fields)')
except AssertionError:
    print(f'  FAIL: invalid Avro structure in $file')
    sys.exit(1)
except Exception as e:
    print(f'  FAIL: {e}')
    sys.exit(1)
" || HAS_ERROR=true
}

validate_json() {
  local file="$1"
  python3 -c "
import json, sys
try:
    schema = json.load(open('$file'))
    assert schema.get('\$schema', '').startswith('http')
    assert 'properties' in schema
    title = schema.get('title', 'unknown')
    count = len(schema['properties'])
    print(f'  OK: {title} ({count} properties)')
except AssertionError:
    print(f'  FAIL: invalid JSON Schema structure in $file')
    sys.exit(1)
except Exception as e:
    print(f'  FAIL: {e}')
    sys.exit(1)
" || HAS_ERROR=true
}

validate_proto() {
  local file="$1"
  if ! grep -q 'syntax = "proto3"' "$file"; then
    echo "  FAIL: missing proto3 syntax in $file"
    HAS_ERROR=true
    return
  fi
  local name
  name=$(basename "$file")
  echo "  OK: $name"
}

check_meta() {
  local file="$1"
  python3 -c "
import json, sys
try:
    meta = json.load(open('$file'))
    for r in ['name', 'type', 'version', 'compatibility']:
        assert r in meta, f'Missing field: {r}'
    print(f'  OK: {meta[\"name\"]} v{meta[\"version\"]} ({meta[\"type\"]})')
except Exception as e:
    print(f'  FAIL: {e}')
    sys.exit(1)
" || HAS_ERROR=true
}

echo "=== Validating Avro ==="
for f in "$SCHEMAS_DIR"/avro/*/v*/schema.avsc; do
  [ -f "$f" ] || continue
  echo "Validating: $f"
  validate_avro "$f"
done

echo "=== Validating JSON ==="
for f in "$SCHEMAS_DIR"/json/*/v*/schema.json; do
  [ -f "$f" ] || continue
  echo "Validating: $f"
  validate_json "$f"
done

echo "=== Validating Protobuf ==="
for f in "$SCHEMAS_DIR"/protobuf/*/v*/schema.proto; do
  [ -f "$f" ] || continue
  echo "Validating: $f"
  validate_proto "$f"
done

echo "=== Checking metadata ==="
for f in "$SCHEMAS_DIR"/*/*/v*/.meta.json; do
  [ -f "$f" ] || continue
  echo "Checking: $f"
  check_meta "$f"
done

if [ "$HAS_ERROR" = true ]; then
  echo "❌ Validation failed"
  exit 1
fi

echo "✅ All schemas valid"
