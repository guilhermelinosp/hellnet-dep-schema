#!/usr/bin/env bash
# Check schema compatibility against Apicurio Registry before registering.
# Usage: ./check-compatibility.sh --registry http://localhost:8085 --group default --schema schemas/avro/my-schema/v1
set -euo pipefail

REGISTRY=""
GROUP="default"
SCHEMA_DIR=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --registry) REGISTRY="$2"; shift 2 ;;
    --group)    GROUP="$2"; shift 2 ;;
    --schema)   SCHEMA_DIR="$2"; shift 2 ;;
    *) echo "Unknown: $1"; exit 1 ;;
  esac
done

if [ -z "$REGISTRY" ] || [ -z "$SCHEMA_DIR" ]; then
  echo "Usage: $0 --registry <url> --group <group> --schema <dir>"
  exit 1
fi

META="$SCHEMA_DIR/.meta.json"
[ -f "$META" ] || { echo "ERROR: metadata not found: $META"; exit 1; }

NAME=$(python3 -c "import json; print(json.load(open('$META'))['name'])")
COMPAT=$(python3 -c "import json; print(json.load(open('$META'))['compatibility'])")

# Find schema file
FILE=""
for ext in avsc json proto; do
  f="$SCHEMA_DIR/schema.$ext"
  [ -f "$f" ] && { FILE="$f"; break; }
done
[ -z "$FILE" ] && { echo "ERROR: schema file not found in $SCHEMA_DIR"; exit 1; }

# Set compatibility rule
echo "Setting compatibility rule: $COMPAT for $NAME"
curl -s -X PUT "$REGISTRY/apis/registry/v2/groups/$GROUP/artifacts/$NAME/rules" \
  -H "Content-Type: application/json" \
  -d "{\"config\": \"$COMPAT\", \"ruleType\": \"COMPATIBILITY\"}" || true

# Test compatibility
echo "Testing compatibility..."
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$REGISTRY/apis/registry/v2/groups/$GROUP/artifacts/$NAME/test" \
  -H "Content-Type: application/json" \
  --data-binary "@$FILE")

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -n -1)

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "204" ]; then
  echo "  ✅ Compatibility check passed"
else
  echo "  ❌ Compatibility check FAILED (HTTP $HTTP_CODE): $BODY"
  exit 1
fi
