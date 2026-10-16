#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="${REPO_DIR}/bin/e3d-code"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/e3d-code-lifecycle.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

ROOT="${TMP_DIR}/root"
STATE="${TMP_DIR}/state"
SPEC="${ROOT}/spec.md"
FAKE_CODEX="${TMP_DIR}/codex"
mkdir -p "${ROOT}/tests"

cat > "$SPEC" <<'EOF'
# Lifecycle Spec

## Phase 1 - Small API

<!-- runner:model=mini -->
<!-- runner:verify=bash tests/generated.sh -->

Implement the behavior and its test.

## Phase 2 - Final Review

<!-- runner:verify=bash tests/generated.sh -->

Review the completed implementation.
EOF

cat > "$FAKE_CODEX" <<'EOF'
#!/usr/bin/env bash
prompt="$(cat)"
printf '%s\n' "$@" >> "${FAKE_MODEL_LOG}"
printf '%s\n' "$prompt" >> "${FAKE_PROMPT_LOG}"
if grep -F "Implement Phase 1" <<< "$prompt" >/dev/null; then
  printf 'implemented\n' > "${FAKE_ROOT}/result.txt"
  cat > "${FAKE_ROOT}/tests/generated.sh" <<'TEST'
#!/usr/bin/env bash
set -euo pipefail
test "$(cat result.txt)" = "implemented"
TEST
  mkdir -p "${FAKE_STATE}/summaries"
  cat > "${FAKE_STATE}/summaries/phase-1.md" <<'SUMMARY'
## Implementation Handoff

- Changes: generated result and regression test.
- Tests: `bash tests/generated.sh`.
- Follow-ups: none.
SUMMARY
elif grep -F "Implement Phase 2" <<< "$prompt" >/dev/null; then
  grep -F "phase-1.md" <<< "$prompt" >/dev/null
  grep -F "gpt-5.5" "${FAKE_MODEL_LOG}" >/dev/null
  cat > "${FAKE_STATE}/summaries/phase-2.md" <<'SUMMARY'
## Implementation Handoff

- Review: no issues found.
- Tests: `bash tests/generated.sh`.
- Follow-ups: none.
SUMMARY
fi
EOF
chmod +x "$FAKE_CODEX"

if COMMON_READ_FILES="spec.md" ROOT_DIR="$ROOT" VERIFY_SHELL="missing-verification-shell" \
  "$RUNNER" "$SPEC" --preflight > "${TMP_DIR}/preflight" 2>&1; then
  echo "preflight unexpectedly accepted a missing verification shell" >&2
  exit 1
fi
grep -F "verification shell not found on PATH" "${TMP_DIR}/preflight" >/dev/null

output="$(
  COMMON_READ_FILES="spec.md" \
  ROOT_DIR="$ROOT" \
  STATE_DIR="$STATE" \
  CONTEXT_FILE="${STATE}/context.md" \
  MANIFEST_FILE="${STATE}/manifest.tsv" \
  SUMMARY_DIR="${STATE}/summaries" \
  CODEX_BIN="$FAKE_CODEX" \
  CODEX_SKIP_GIT_REPO_CHECK=1 \
  FAKE_ROOT="$ROOT" \
  FAKE_STATE="$STATE" \
  FAKE_MODEL_LOG="${TMP_DIR}/models" \
  FAKE_PROMPT_LOG="${TMP_DIR}/prompts" \
  "$RUNNER" "$SPEC" all
)"

printf '%s\n' "$output" | grep -F "Verification: running bash tests/generated.sh" >/dev/null
printf '%s\n' "$output" | grep -F "Status: phase 2 completed." >/dev/null
grep -F $'1\tcodex\tgpt-5.4-mini' <(cut -f3,5,6 "${STATE}/manifest.tsv") >/dev/null
grep -F $'2\tcodex\tgpt-5.5' <(cut -f3,5,6 "${STATE}/manifest.tsv") >/dev/null
grep -F "generated result and regression test" "${STATE}/summaries/phase-1.md" >/dev/null
grep -F 'passed: `bash tests/generated.sh`' "${STATE}/summaries/phase-1.md" >/dev/null
grep -F "${STATE}/summaries/phase-1.md" "${TMP_DIR}/prompts" >/dev/null

single_state="${TMP_DIR}/single-state"
mkdir -p "${single_state}/summaries"
cp "${STATE}/summaries/phase-1.md" "${single_state}/summaries/phase-1.md"

single_output="$(
  COMMON_READ_FILES="spec.md" \
  ROOT_DIR="$ROOT" \
  STATE_DIR="$single_state" \
  CONTEXT_FILE="${single_state}/context.md" \
  MANIFEST_FILE="${single_state}/manifest.tsv" \
  SUMMARY_DIR="${single_state}/summaries" \
  "$RUNNER" "$SPEC" 2 --dry-run --verbose
)"

[[ -f "${single_state}/context.md" ]]
printf '%s\n' "$single_output" | grep -F -- "- ${single_state}/context.md" >/dev/null
printf '%s\n' "$single_output" | grep -F -- "- ${single_state}/summaries/phase-1.md" >/dev/null

disabled_state="${TMP_DIR}/disabled-state"
mkdir -p "${disabled_state}/summaries"
cp "${STATE}/summaries/phase-1.md" "${disabled_state}/summaries/phase-1.md"

disabled_output="$(
  COMMON_READ_FILES="spec.md" \
  ROOT_DIR="$ROOT" \
  STATE_DIR="$disabled_state" \
  CONTEXT_FILE="${disabled_state}/context.md" \
  MANIFEST_FILE="${disabled_state}/manifest.tsv" \
  SUMMARY_DIR="${disabled_state}/summaries" \
  USE_SHARED_CONTEXT=0 \
  USE_PHASE_SUMMARIES=0 \
  "$RUNNER" "$SPEC" 2 --dry-run --verbose
)"

[[ ! -f "${disabled_state}/context.md" ]]
if printf '%s\n' "$disabled_output" | grep -F -- "- ${disabled_state}/summaries/phase-1.md" >/dev/null; then
  echo "single-phase run unexpectedly included summaries with USE_PHASE_SUMMARIES=0" >&2
  exit 1
fi

failing_spec="${ROOT}/failing.md"
cat > "$failing_spec" <<'EOF'
## Phase 1 - Implementation
<!-- runner:verify=false -->
Implement.

## Phase 2 - Must Not Run
Implement later.
EOF

if COMMON_READ_FILES="spec.md" ROOT_DIR="$ROOT" STATE_DIR="${TMP_DIR}/failed-state" \
  CODEX_BIN="$FAKE_CODEX" CODEX_SKIP_GIT_REPO_CHECK=1 FAKE_ROOT="$ROOT" \
  FAKE_STATE="${TMP_DIR}/failed-state" FAKE_MODEL_LOG="${TMP_DIR}/failed-models" \
  FAKE_PROMPT_LOG="${TMP_DIR}/failed-prompts" \
  "$RUNNER" "$failing_spec" all >/dev/null 2>&1; then
  echo "verification failure unexpectedly succeeded" >&2
  exit 1
fi
[[ "$(grep -c -- '--model' "${TMP_DIR}/failed-models")" == "1" ]]
grep -F $'1\tImplementation\tcodex\tgpt-5.4\texec\t0\t1' "${TMP_DIR}/failed-state/manifest.tsv" >/dev/null

provider_failure_state="${TMP_DIR}/provider-failure-state"
provider_failure_bin="${TMP_DIR}/failing-codex"
cat > "$provider_failure_bin" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
exit 7
EOF
chmod +x "$provider_failure_bin"

if COMMON_READ_FILES="spec.md" ROOT_DIR="$ROOT" STATE_DIR="$provider_failure_state" \
  CODEX_BIN="$provider_failure_bin" CODEX_SKIP_GIT_REPO_CHECK=1 \
  "$RUNNER" "$SPEC" 1 >/dev/null 2>&1; then
  echo "provider failure unexpectedly succeeded" >&2
  exit 1
fi
grep -F $'1\tSmall API\tcodex\tgpt-5.4-mini\texec\t0\t7' "${provider_failure_state}/manifest.tsv" >/dev/null
grep -F "Not run because the provider exited with status 7" \
  "${provider_failure_state}/summaries/phase-1.md" >/dev/null

echo "phase-lifecycle: ok"
