#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="${REPO_DIR}/bin/spec2code"
SPEC_FILE="${REPO_DIR}/examples/feature-ticket.md"

bash -n "$RUNNER"

list_output="$(
  cd "$REPO_DIR" &&
  COMMON_READ_FILES="" "$RUNNER" "$SPEC_FILE" --list
)"
printf '%s\n' "$list_output" | grep -F $'Phase 1\tcodex\tgpt-5.4-mini\tCore Parser' >/dev/null

dry_run_output="$(
  cd "$REPO_DIR" &&
  COMMON_READ_FILES="" "$RUNNER" "$SPEC_FILE" 2 --dry-run
)"
printf '%s\n' "$dry_run_output" | grep -F "Status: dry-run only; Codex was not started." >/dev/null
if printf '%s\n' "$dry_run_output" | grep -F -- "- examples/reporting-notes.md" >/dev/null; then
  echo "default dry-run unexpectedly printed annotated read files" >&2
  exit 1
fi

verbose_dry_run_output="$(
  cd "$REPO_DIR" &&
  COMMON_READ_FILES="" "$RUNNER" "$SPEC_FILE" 2 --dry-run --verbose
)"
printf '%s\n' "$verbose_dry_run_output" | grep -F -- "- examples/reporting-notes.md" >/dev/null
printf '%s\n' "$verbose_dry_run_output" | grep -F "Verification hints:" >/dev/null
printf '%s\n' "$verbose_dry_run_output" | grep -F -- "- bash tests/report-writer.sh" >/dev/null

echo "phase-9-docs-example: ok"
