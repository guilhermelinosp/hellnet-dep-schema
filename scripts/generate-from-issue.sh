#!/usr/bin/env bash
set -euo pipefail

ISSUE_BODY="$1"

# ---- Parse fields from GitHub issue body ----
# The body contains YAML frontmatter with name, type, compatibility, and fields

NAME=$(echo "$ISSUE_BODY" | grep -A1 '### Schema name' | tail -1 | xargs)
TYPE=$(echo "$ISSUE_BODY" | grep -A1 '### Format' | tail -1 | xargs)
COMPAT=$(echo "$ISSUE_BODY" | grep -A1 '### Compatibility' | tail -1 | xargs)
FIELDS=$(echo "$ISSUE_BODY" | sed -n '/### Fields/,/### Description/p' | sed '1d;$d')

# Sanitize
NAME="${NAME:-unknown}"
TYPE="${TYPE:-avro}"
COMPAT="${COMPAT:-BACKWARD}"

VERSION=1

# Check for existing versions
SCHEMA_DIR="schemas/${TYPE}/${NAME}"
if [ -d "$SCHEMA_DIR" ]; then
  LAST_VERSION=$(ls -1 "$SCHEMA_DIR" | grep -E '^v[0-9]+$' | sort -t'v' -k2 -n | tail -1)
  if [ -n "$LAST_VERSION" ]; then
    VERSION=$(( ${LAST_VERSION#v} + 1 ))
  fi
fi

mkdir -p "$SCHEMA_DIR/v${VERSION}"

case "$TYPE" in
  avro)
    generate_avro "$NAME" "$FIELDS" "$SCHEMA_DIR/v${VERSION}/schema.avsc"
    ;;
  json)
    generate_json "$NAME" "$FIELDS" "$SCHEMA_DIR/v${VERSION}/schema.json"
    ;;
  protobuf)
    generate_protobuf "$NAME" "$FIELDS" "$SCHEMA_DIR/v${VERSION}/schema.proto"
    ;;
esac

# Write compatibility config
cat > "$SCHEMA_DIR/v${VERSION}/.meta.json" << EOF
{
  "name": "$NAME",
  "type": "$TYPE",
  "version": $VERSION,
  "compatibility": "$COMPAT",
  "createdAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

echo "NAME=$NAME"
echo "TYPE=$TYPE"
echo "VERSION=$VERSION"
echo "PATH=${SCHEMA_DIR}/v${VERSION}/schema.${TYPE}"

# ---- Generator functions ----

generate_avro() {
  local name="$1"
  local fields_yaml="$2"
  local output="$3"

  cat > "$output" << AVRO_EOF
{
  "namespace": "hellnet.events",
  "type": "record",
  "name": "$(echo "$name" | sed 's/-/_/g' | sed 's/[^a-zA-Z0-9_]/_/g')",
  "doc": "Auto-generated from hellnet-dep-schema",
  "fields": [
AVRO_EOF

  # Parse fields from YAML and generate Avro field entries
  echo "$fields_yaml" | while IFS= read -r line; do
    local field_type=$(echo "$line" | grep -oP 'type:\s*\K\S+' || true)
    local field_name=$(echo "$line" | grep -oP 'name:\s*\K\S+' || true)
    local field_default=$(echo "$line" | grep -oP 'default:\s*\K\S+' || true)
    local field_required=$(echo "$line" | grep -oP 'required:\s*\K\S+' || true)

    if [ -z "$field_name" ] || [ -z "$field_type" ]; then
      continue
    fi

    # Map YAML types to Avro types
    case "$field_type" in
      string) avro_type="string" ;;
      int)    avro_type="int" ;;
      long)   avro_type="long" ;;
      double) avro_type="double" ;;
      float)  avro_type="float" ;;
      bool)   avro_type="boolean" ;;
      array)  avro_type="array" ;;
      object) avro_type="record" ;;
      *)      avro_type="string" ;;
    esac

    # Build Avro field
    echo -n '    { "name": "'"$field_name"'", "type": '
    if [ "$field_required" = "false" ] || [ -n "$field_default" ]; then
      echo -n '["null", "'"$avro_type"'"]'
    else
      echo -n '"'"$avro_type"'"'
    fi

    if [ -n "$field_default" ]; then
      echo -n ', "default": '"$field_default"
    fi

    echo ' }'
  done | paste -sd ',' - >> "$output"

  echo '  ]' >> "$output"
  echo '}' >> "$output"

  # Validate with python
  python3 -c "import json; json.load(open('$output'))" || {
    echo "ERROR: Invalid Avro schema generated"
    exit 1
  }
}

generate_json() {
  local name="$1"
  local fields_yaml="$2"
  local output="$3"

  cat > "$output" << JSON_EOF
{
  "\$schema": "http://json-schema.org/draft-07/schema#",
  "title": "$(echo "$name" | sed 's/-/ /g' | sed 's/\b\(.\)/\u\1/g')",
  "type": "object",
  "properties": {
JSON_EOF

  echo "$fields_yaml" | while IFS= read -r line; do
    local field_name=$(echo "$line" | grep -oP 'name:\s*\K\S+' || true)
    local field_type=$(echo "$line" | grep -oP 'type:\s*\K\S+' || true)
    local field_desc=$(echo "$line" | grep -oP 'description:\s*\K.*' || true)
    local field_required=$(echo "$line" | grep -oP 'required:\s*\K\S+' || true)

    if [ -z "$field_name" ] || [ -z "$field_type" ]; then
      continue
    fi

    case "$field_type" in
      string) js_type="string" ;;
      int|long) js_type="integer" ;;
      double|float) js_type="number" ;;
      bool)   js_type="boolean" ;;
      array)  js_type="array" ;;
      object) js_type="object" ;;
      *)      js_type="string" ;;
    esac

    echo -n '    "'"$field_name"'": { "type": "'"$js_type"'"'
    if [ -n "$field_desc" ]; then
      echo -n ', "description": "'"$field_desc"'"'
    fi
    echo ' }'
  done | paste -sd ',' - >> "$output"

  echo '  },' >> "$output"

  # Required fields
  echo -n '  "required": [' >> "$output"
  first=true
  echo "$fields_yaml" | while IFS= read -r line; do
    local field_name=$(echo "$line" | grep -oP 'name:\s*\K\S+' || true)
    local field_required=$(echo "$line" | grep -oP 'required:\s*\K\S+' || true)
    if [ -n "$field_name" ] && { [ "$field_required" = "true" ] || [ -z "$field_required" ]; }; then
      if [ "$first" = true ]; then
        first=false
      else
        echo -n ', '
      fi
      echo -n '"'"$field_name"'"'
    fi
  done >> "$output"
  echo ']' >> "$output"
  echo '}' >> "$output"

  # Validate JSON
  python3 -c "import json; json.load(open('$output'))" || {
    echo "ERROR: Invalid JSON Schema generated"
    exit 1
  }
}

generate_protobuf() {
  local name="$1"
  local fields_yaml="$2"
  local output="$3"

  local proto_name=$(echo "$name" | sed 's/-/_/g' | sed 's/[^a-zA-Z0-9_]//g')
  local package="hellnet.events.v1"

  cat > "$output" << PROTO_EOF
syntax = "proto3";
package $package;

option csharp_namespace = "Hellnet.Events.V1";

message $(echo "$name" | sed 's/-//g' | sed 's/^./\u&/;s/-\(.\)/\u\1/g') {
PROTO_EOF

  local idx=0
  echo "$fields_yaml" | while IFS= read -r line; do
    local field_name=$(echo "$line" | grep -oP 'name:\s*\K\S+' || true)
    local field_type=$(echo "$line" | grep -oP 'type:\s*\K\S+' || true)

    if [ -z "$field_name" ] || [ -z "$field_type" ]; then
      continue
    fi

    case "$field_type" in
      string) pb_type="string" ;;
      int)    pb_type="int32" ;;
      long)   pb_type="int64" ;;
      double) pb_type="double" ;;
      float)  pb_type="float" ;;
      bool)   pb_type="bool" ;;
      array)  pb_type="repeated string" ;;
      *)      pb_type="string" ;;
    esac

    idx=$((idx + 1))
    echo "  $pb_type $field_name = $idx;"
  done >> "$output"

  echo '}' >> "$output"

  # Basic validation
  if ! grep -q 'syntax = "proto3"' "$output"; then
    echo "ERROR: Invalid protobuf schema generated"
    exit 1
  fi
}
