#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

issue_21_body=$(cat <<'ISSUE'
### Schema name

fast-ride-accepted

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
)

output=$(cd "$work_dir" && bash "$repo_root/scripts/generate-from-issue.sh" "$issue_21_body")
grep -q '^NAME=fast-ride-accepted$' <<<"$output"
grep -q '^TYPE=avro$' <<<"$output"
grep -q '^VERSION=1$' <<<"$output"

schema="$work_dir/schemas/avro/fast-ride-accepted/v1/schema.avsc"
python3 - "$schema" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    document = json.load(stream)

fields = {field["name"]: field for field in document["fields"]}
assert fields["eventVersion"]["type"] == "int"
assert fields["eventVersion"]["default"] == 1
assert fields["eventId"]["type"] == "string"
PY

echo "PASS: Issue #21 generated fast-ride-accepted v1 with valid Avro JSON"
