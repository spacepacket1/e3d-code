#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="${REPO_DIR}/bin/spec2code"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/spec2code-phase8.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

SPEC_FILE="${TMP_DIR}/phase-8-spec.md"
mkdir -p "${TMP_DIR}/docs"
printf 'phase 8 notes\n' > "${TMP_DIR}/docs/annotated-read.md"

cat > "$SPEC_FILE" <<'EOF'
# Temporary Spec

## Phase 1 - Simple API

<!-- codex:model=gpt-5.4-mini -->
<!-- codex:read=docs/annotated-read.md -->
<!-- codex:verify=npm test -->

Keep this phase scoped.
EOF

bash -n "$RUNNER"

list_output="$(
  cd "$REPO_DIR" &&
  COMMON_READ_FILES="" ROOT_DIR="$TMP_DIR" "$RUNNER" "$SPEC_FILE" --list
)"
printf '%s\n' "$list_output" | grep -F $'Phase 1\tcodex\tgpt-5.4-mini\tSimple API' >/dev/null

override_output="$(
  cd "$REPO_DIR" &&
  COMMON_READ_FILES="" ROOT_DIR="$TMP_DIR" MODEL_OVERRIDES="1:gpt-5.5" "$RUNNER" "$SPEC_FILE" --list
)"
printf '%s\n' "$override_output" | grep -F $'Phase 1\tcodex\tgpt-5.5\tSimple API' >/dev/null

dry_run_output="$(
  cd "$REPO_DIR" &&
  COMMON_READ_FILES="" ROOT_DIR="$TMP_DIR" "$RUNNER" "$SPEC_FILE" 1 --dry-run
)"
printf '%s\n' "$dry_run_output" | grep -F "Model: gpt-5.4-mini" >/dev/null
printf '%s\n' "$dry_run_output" | grep -F "Status: dry-run only; Codex was not started." >/dev/null
if printf '%s\n' "$dry_run_output" | grep -F -- "- docs/annotated-read.md" >/dev/null; then
  echo "default dry-run unexpectedly printed annotated read files" >&2
  exit 1
fi

verbose_dry_run_output="$(
  cd "$REPO_DIR" &&
  COMMON_READ_FILES="" ROOT_DIR="$TMP_DIR" "$RUNNER" "$SPEC_FILE" 1 --dry-run --verbose
)"
printf '%s\n' "$verbose_dry_run_output" | grep -F -- "- docs/annotated-read.md" >/dev/null
printf '%s\n' "$verbose_dry_run_output" | grep -F "Verification hints:" >/dev/null
printf '%s\n' "$verbose_dry_run_output" | grep -F -- "- npm test" >/dev/null

echo "phase-8-annotations: ok"
