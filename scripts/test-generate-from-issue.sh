#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

issue_body() {
  local schema_name="$1"
  cat <<'ISSUE' | sed "s/__SCHEMA_NAME__/$schema_name/"
### Schema name

__SCHEMA_NAME__

### Format

avro

### Compatibility level

BACKWARD

### Fields (YAML)

```yaml
- name: eventId
  type: string
  required: true
- name: eventVersion
  type: int
  required: true
  default: 1
- name: occurredAt
  type: long
  required: true
- name: rideId
  type: string
  required: true
- name: driverId
  type: string
  required: true
```

### Description (optional)

_No response_
ISSUE
}

output=$(cd "$work_dir" && bash "$repo_root/scripts/generate-from-issue.sh" "$(issue_body fast-ride-requested)")
grep -q '^NAME=fast-ride-requested$' <<<"$output"
grep -q '^TYPE=avro$' <<<"$output"
grep -q '^VERSION=1$' <<<"$output"

requested_schema="$work_dir/schemas/avro/fast-ride-requested/v1/schema.avsc"
python3 - "$requested_schema" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    document = json.load(stream)

assert document["namespace"] == "fast.events.ride.v1"
assert document["name"] == "RideRequestedV1"
assert document["doc"] == "Published when a ride is requested in Fast."
PY

output=$(cd "$work_dir" && bash "$repo_root/scripts/generate-from-issue.sh" "$(issue_body fast-ride-accepted)")
grep -q '^NAME=fast-ride-accepted$' <<<"$output"
grep -q '^TYPE=avro$' <<<"$output"
grep -q '^VERSION=1$' <<<"$output"

schema="$work_dir/schemas/avro/fast-ride-accepted/v1/schema.avsc"
python3 - "$schema" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    document = json.load(stream)

assert document["namespace"] == "fast.events.ride.v1"
assert document["name"] == "RideAcceptedV1"
assert document["doc"] == "Published when a driver accepts a ride in Fast."
fields = {field["name"]: field for field in document["fields"]}
assert fields["eventVersion"]["type"] == "int"
assert fields["eventVersion"]["default"] == 1
assert fields["eventId"]["type"] == "string"
PY

echo "PASS: Fast Avro examples generated with valid namespace, name, doc, required, and default"
