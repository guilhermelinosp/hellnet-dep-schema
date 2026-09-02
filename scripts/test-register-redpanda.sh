#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH=; cd -- "$(dirname -- "$0")" && pwd)
SCRIPT="$SCRIPT_DIR/register-redpanda.sh"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/schemas/avro/fast-ride-requested/v1" "$TMP_DIR/schemas/avro/fast-ride-accepted/v1"
cat > "$TMP_DIR/schemas/avro/fast-ride-requested/v1/schema.avsc" <<'EOF'
{"namespace":"fast.events.ride.v1","type":"record","name":"RideRequestedV1","fields":[]}
EOF
cat > "$TMP_DIR/schemas/avro/fast-ride-accepted/v1/schema.avsc" <<'EOF'
{"namespace":"fast.events.ride.v1","type":"record","name":"RideAcceptedV1","fields":[]}
EOF

output=$(SCHEMAS_DIR="$TMP_DIR/schemas/avro" bash "$SCRIPT" --dry-run)
[[ "$output" == *"subject=fast-ride-requested"* ]]
[[ "$output" == *"topic=ride.requested.v1"* ]]
[[ "$output" == *"subject=fast-ride-accepted"* ]]
[[ "$output" == *"topic=ride.accepted.v1"* ]]
[[ "$output" == *"endpoint=http://localhost:8081/subjects/fast-ride-requested/versions"* ]]

mkdir -p "$TMP_DIR/schemas/avro/not-fast/v1"
printf '%s\n' '{"type":"record","name":"Bad","namespace":"bad","fields":[]}' \
  > "$TMP_DIR/schemas/avro/not-fast/v1/schema.avsc"
if SCHEMAS_DIR="$TMP_DIR/schemas/avro" bash "$SCRIPT" --dry-run >/dev/null 2>&1; then
  echo "expected invalid directory to be rejected" >&2
  exit 1
fi

echo "register-redpanda tests passed (no network or rpk required)"
