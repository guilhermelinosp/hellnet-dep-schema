#!/usr/bin/env bash
set -euo pipefail

# === Helpers ===

# Parse issue body fields from GitHub issue template
parse_issue_body() {
  local body="$1"
  NAME=$(echo "$body" | sed -n '/### Schema name/{n;p;}' | xargs)
  TYPE=$(echo "$body" | sed -n '/### Format/{n;p;}' | xargs)
  COMPAT=$(echo "$body" | sed -n '/### Compatibility/{n;p;}' | xargs)
  FIELDS=$(echo "$body" | sed -n '/### Fields/,/### [A-Z]/p' | sed '1d;$d' | grep -v '^$')

  NAME="${NAME:-unknown}"
  TYPE="${TYPE:-avro}"
  COMPAT="${COMPAT:-BACKWARD}"
  # GitHub issue forms rejects "NONE" keyword, use "NO_CHECK" instead
  if [ "$COMPAT" = "NO_CHECK" ]; then
    COMPAT="NONE"
  fi
}

# Parse YAML field blocks into pipe-separated lines: name|type|default|required
parse_fields() {
  echo "$1" | awk '
    BEGIN { f=""; t=""; d=""; r=""; sep="|" }
    /^- / {
      if (f != "") print f sep t sep d sep r
      f=substr($0, index($0,": ")+2)
      t=""; d=""; r=""
    }
    /^  type:/     { t=substr($0, index($0,": ")+2) }
    /^  default:/  { d=substr($0, index($0,": ")+2) }
    /^  required:/ { r=substr($0, index($0,": ")+2) }
    END { if (f != "") print f sep t sep d sep r }
  '
}

# Validate JSON file
validate_json_file() {
  python3 -c "import json; json.load(open('$1'))" 2>/dev/null || {
    echo "ERROR: Invalid JSON in $1"
    exit 1
  }
}

# === Generator: Avro ===

generate_avro() {
  local name="$1" fields="$2" output="$3"
  local avro_name
  avro_name=$(echo "$name" | tr '-' '_' | sed 's/[^a-zA-Z0-9_]/_/g')

  exec 3>"$output"
  echo '{' >&3
  echo '  "namespace": "hellnet.events",' >&3
  echo '  "type": "record",' >&3
  echo "  \"name\": \"$avro_name\"," >&3
  echo '  "doc": "Auto-generated from hellnet-dep-schema",' >&3
  echo '  "fields": [' >&3

  local first=true
  while IFS='|' read -r fname ftype fdefault frequired; do
    [ -z "$fname" ] || [ -z "$ftype" ] && continue

    [ "$first" = false ] && echo "," >&3
    first=false

    echo -n '    { "name": "'"$fname"'", "type": ' >&3
    if [ "$frequired" = "false" ] || [ -n "$fdefault" ]; then
      echo -n '["null", "'"$ftype"'"]' >&3
    else
      echo -n '"'"$ftype"'"' >&3
    fi
    [ -n "$fdefault" ] && echo -n ', "default": '"$fdefault" >&3
    echo -n ' }' >&3
  done < <(parse_fields "$fields")

  echo '' >&3
  echo '  ]' >&3
  echo '}' >&3
  exec 3>&-

  validate_json_file "$output"
}

# === Generator: JSON Schema ===

generate_json() {
  local name="$1" fields="$2" output="$3"
  local title
  title=$(echo "$name" | tr '-' ' ' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1')

  exec 3>"$output"
  echo '{' >&3
  echo '  "$schema": "http://json-schema.org/draft-07/schema#",' >&3
  echo "  \"title\": \"$title\"," >&3
  echo '  "type": "object",' >&3
  echo '  "properties": {' >&3

  local first=true
  while IFS='|' read -r fname ftype fdefault frequired; do
    [ -z "$fname" ] && continue
    [ "$first" = false ] && echo "," >&3
    first=false
    echo -n "    \"$fname\": { \"type\": \"$ftype\" }" >&3
  done < <(parse_fields "$fields")

  echo '' >&3
  echo '  },' >&3
  echo '  "required": [' >&3

  local first=true
  while IFS='|' read -r fname ftype fdefault frequired; do
    [ -z "$fname" ] && continue
    if [ "$frequired" != "false" ]; then
      [ "$first" = false ] && echo "," >&3
      first=false
      echo -n "    \"$fname\"" >&3
    fi
  done < <(parse_fields "$fields")

  echo '' >&3
  echo '  ]' >&3
  echo '}' >&3
  exec 3>&-

  validate_json_file "$output"
}

# === Generator: Protobuf ===

generate_protobuf() {
  local name="$1" fields="$2" output="$3"
  local msg_name
  msg_name=$(echo "$name" | awk -F'-' '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1' | tr -d ' ')

  exec 3>"$output"
  echo 'syntax = "proto3";' >&3
  echo 'package hellnet.events.v1;' >&3
  echo '' >&3
  echo 'option csharp_namespace = "Hellnet.Events.V1";' >&3
  echo '' >&3
  echo "message $msg_name {" >&3

  local idx=0
  while IFS='|' read -r fname ftype fdefault frequired; do
    [ -z "$fname" ] && continue
    idx=$((idx + 1))
    echo "  $ftype $fname = $idx;" >&3
  done < <(parse_fields "$fields")

  echo '}' >&3
  exec 3>&-

  if ! grep -q 'syntax = "proto3"' "$output"; then
    echo "ERROR: Invalid protobuf schema generated"
    exit 1
  fi
}

# === Main ===

parse_issue_body "${1:-}"

# === Security: strictly validate untrusted inputs from the issue body ===
# NAME/TYPE come from the issue body and are later used in shell commands
# (branch name, tag, commit message, PR title). Restrict to a safe allowlist
# to prevent command injection in the workflow steps that consume them.
if ! echo "$NAME" | grep -qE '^[A-Za-z0-9_-]+$'; then
  echo "ERROR: invalid schema name (allowed: [A-Za-z0-9_-]): $NAME"
  exit 1
fi
case "$TYPE" in
  avro|json|protobuf) ;;
  *) echo "ERROR: invalid schema type (allowed: avro|json|protobuf): $TYPE"; exit 1 ;;
esac

VERSION=1
SCHEMA_DIR="schemas/${TYPE}/${NAME}"

# Auto-increment version if dir exists
if [ -d "$SCHEMA_DIR" ]; then
  last=$(ls -1 "$SCHEMA_DIR" 2>/dev/null | grep -E '^v[0-9]+$' | sort -t'v' -k2 -n | tail -1)
  if [ -n "$last" ]; then
    VERSION=$(( ${last#v} + 1 ))
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
  *)
    echo "ERROR: unknown type: $TYPE"
    exit 1
    ;;
esac

# Write metadata
cat > "$SCHEMA_DIR/v${VERSION}/.meta.json" << META
{
  "name": "$NAME",
  "type": "$TYPE",
  "version": $VERSION,
  "compatibility": "$COMPAT",
  "createdAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
META

echo "NAME=$NAME"
echo "TYPE=$TYPE"
echo "VERSION=$VERSION"
EXT="avsc"
[ "$TYPE" = "json" ] && EXT="json"
[ "$TYPE" = "protobuf" ] && EXT="proto"
echo "PATH=${SCHEMA_DIR}/v${VERSION}/schema.${EXT}"
