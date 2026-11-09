#!/usr/bin/env bash
set -euo pipefail

# Regression tests for leading-zero phase arguments (--from/--to).
# Bash arithmetic treats leading-zero numbers as octal, so "08" and "09"
# used to fail validation with "value too great for base". Values are now
# normalized to base 10 in validate_phase_range().

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="${REPO_DIR}/bin/e3d-code"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/e3d-code-leading-zero.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

ROOT="${TMP_DIR}/root"
STATE="${TMP_DIR}/state"
mkdir -p "${ROOT}/tests" "${STATE}/summaries"
SPEC="${ROOT}/spec.md"

cat > "$SPEC" <<'EOF'
# Leading Zero Spec

## Phase 1 - One
<!-- runner:model=mini -->
<!-- runner:verify=true -->

## Phase 2 - Two
<!-- runner:model=mini -->
<!-- runner:verify=true -->

## Phase 3 - Three
<!-- runner:model=mini -->
<!-- runner:verify=true -->

## Phase 4 - Four
<!-- runner:model=mini -->
<!-- runner:verify=true -->

## Phase 5 - Five
<!-- runner:model=mini -->
<!-- runner:verify=true -->

## Phase 6 - Six
<!-- runner:model=mini -->
<!-- runner:verify=true -->

## Phase 7 - Seven
<!-- runner:model=mini -->
<!-- runner:verify=true -->

## Phase 8 - Eight
<!-- runner:model=mini -->
<!-- runner:verify=true -->

## Phase 9 - Nine
<!-- runner:model=mini -->
<!-- runner:verify=true -->

## Phase 10 - Ten
<!-- runner:model=mini -->
<!-- runner:verify=true -->
EOF

run_all() {
  COMMON_READ_FILES="spec.md" \
    ROOT_DIR="$ROOT" \
    STATE_DIR="$STATE" \
    CONTEXT_FILE="${STATE}/context.md" \
    MANIFEST_FILE="${STATE}/manifest.tsv" \
    SUMMARY_DIR="${STATE}/summaries" \
    "$RUNNER" "$SPEC" all --dry-run "$@" 2>&1
}

# 1. Leading zeros 08/09 normalize to decimal and select phases 8 and 9.
output="$(run_all --from 08 --to 09)"
printf '%s\n' "$output" | grep -F "== Phase 8: Eight ==" >/dev/null
printf '%s\n' "$output" | grep -F "== Phase 9: Nine ==" >/dev/null
! printf '%s\n' "$output" | grep -F "== Phase 7: Seven ==" >/dev/null
! printf '%s\n' "$output" | grep -F "== Phase 10: Ten ==" >/dev/null

# 2. Leading-zero single digit boundary (01 -> 1).
output="$(run_all --from 01 --to 01)"
printf '%s\n' "$output" | grep -F "== Phase 1: One ==" >/dev/null
! printf '%s\n' "$output" | grep -F "== Phase 2: Two ==" >/dev/null

# 3. Normal values still work.
output="$(run_all --from 1 --to 3)"
printf '%s\n' "$output" | grep -F "== Phase 1: One ==" >/dev/null
printf '%s\n' "$output" | grep -F "== Phase 3: Three ==" >/dev/null
! printf '%s\n' "$output" | grep -F "== Phase 4: Four ==" >/dev/null

# 4. from > to is rejected even with leading zeros.
if run_all --from 09 --to 08 >/dev/null 2>&1; then
  echo "expected --from 09 --to 08 to be rejected" >&2
  exit 1
fi
if run_all --from 10 --to 08 >/dev/null 2>&1; then
  echo "expected --from 10 --to 08 to be rejected" >&2
  exit 1
fi

# 5. Invalid non-numeric strings are rejected.
if run_all --from abc --to 10 >/dev/null 2>&1; then
  echo "expected --from abc to be rejected" >&2
  exit 1
fi
if run_all --from 1 --to xyz >/dev/null 2>&1; then
  echo "expected --to xyz to be rejected" >&2
  exit 1
fi

# 6. 00 normalizes to 0 without an octal error; no phase 0 exists, so the
#    failure is "range does not include any phases", not an octal error.
if run_all --from 00 --to 00 >/dev/null 2>&1; then
  echo "expected --from 00 --to 00 to select no phases" >&2
  exit 1
fi

echo "phase-leading-zero: ok"
