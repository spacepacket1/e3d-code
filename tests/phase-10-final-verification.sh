#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="${REPO_DIR}/bin/spec2code"
SPEC_FILE="${REPO_DIR}/examples/feature-ticket.md"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/spec2code-phase10.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

PATH="${REPO_DIR}/bin:${PATH}"

bash -n "$RUNNER"

version_output="$(
  cd "$REPO_DIR" &&
  spec2code --version
)"
printf '%s\n' "$version_output" | grep -F "spec2code 0.3.0" >/dev/null

list_output="$(
  cd "$REPO_DIR" &&
  spec2code "$SPEC_FILE" --list
)"
printf '%s\n' "$list_output" | grep -F $'Phase 1\tcodex\tgpt-5.4-mini\tCore Parser' >/dev/null

preflight_output="$(
  cd "$REPO_DIR" &&
  spec2code "$SPEC_FILE" --preflight
)"
printf '%s\n' "$preflight_output" | grep -F "result: ok with 1 warning(s)" >/dev/null

phase_dry_run_output="$(
  cd "$REPO_DIR" &&
  spec2code "$SPEC_FILE" 1 --dry-run
)"
printf '%s\n' "$phase_dry_run_output" | grep -F "== Phase 1: Core Parser ==" >/dev/null
printf '%s\n' "$phase_dry_run_output" | grep -F "Provider: codex" >/dev/null
printf '%s\n' "$phase_dry_run_output" | grep -F "Status: dry-run only; Codex was not started." >/dev/null
if printf '%s\n' "$phase_dry_run_output" | grep -F -- "--- prompt ---" >/dev/null; then
  echo "default dry-run unexpectedly printed full prompt" >&2
  exit 1
fi

verbose_phase_dry_run_output="$(
  cd "$REPO_DIR" &&
  spec2code "$SPEC_FILE" 1 --dry-run --verbose
)"
printf '%s\n' "$verbose_phase_dry_run_output" | grep -F -- "--- prompt ---" >/dev/null

all_dry_run_output="$(
  cd "$REPO_DIR" &&
  spec2code "$SPEC_FILE" all --dry-run
)"
printf '%s\n' "$all_dry_run_output" | grep -F "== Phase 3: Dashboard Widget ==" >/dev/null

unset_verbose_output="$(
  cd "$REPO_DIR" &&
  unset VERBOSE &&
  spec2code "$SPEC_FILE" all --from 1 --to 1 --dry-run
)"
printf '%s\n' "$unset_verbose_output" | grep -F "Status: dry-run only; Codex was not started." >/dev/null

claude_list_output="$(
  cd "$REPO_DIR" &&
  PROVIDER=claude spec2code "$SPEC_FILE" --list
)"
printf '%s\n' "$claude_list_output" | grep -F $'Phase 1\tclaude\thaiku\tCore Parser' >/dev/null

claude_phase_dry_run_output="$(
  cd "$REPO_DIR" &&
  spec2code "$SPEC_FILE" 1 --dry-run --provider claude
)"
printf '%s\n' "$claude_phase_dry_run_output" | grep -F "Provider: claude" >/dev/null
printf '%s\n' "$claude_phase_dry_run_output" | grep -F "Model: haiku" >/dev/null
printf '%s\n' "$claude_phase_dry_run_output" | grep -F "Status: dry-run only; Claude was not started." >/dev/null

fake_codex="${TMP_DIR}/codex"
fake_args="${TMP_DIR}/codex-args"
fake_stdin="${TMP_DIR}/codex-stdin"
fake_claude="${TMP_DIR}/claude"
fake_claude_args="${TMP_DIR}/claude-args"
fake_claude_stdin="${TMP_DIR}/claude-stdin"
mkdir -p "${TMP_DIR}/root"
mkdir -p "${TMP_DIR}/extra-read" "${TMP_DIR}/extra-write"
cat > "$fake_codex" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FAKE_ARGS"
cat > "$FAKE_STDIN"
EOF
chmod +x "$fake_codex"

cat > "$fake_claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FAKE_ARGS"
cat > "$FAKE_STDIN"
EOF
chmod +x "$fake_claude"

(
  cd "$REPO_DIR" &&
  COMMON_READ_FILES="" \
  ROOT_DIR="${TMP_DIR}/root" \
  RUN_VERIFICATION=0 \
  CODEX_BIN="$fake_codex" \
  CODEX_SKIP_GIT_REPO_CHECK=1 \
  ADD_DIRS="${TMP_DIR}/extra-read ${TMP_DIR}/extra-write" \
  FAKE_ARGS="$fake_args" \
  FAKE_STDIN="$fake_stdin" \
  "$RUNNER" "$SPEC_FILE" 1
) >/dev/null

grep -Fx -- "--ephemeral" "$fake_args" >/dev/null
first_five_args="$(sed -n '1,5p' "$fake_args")"
[[ "$first_five_args" == $'--ask-for-approval\non-request\nexec\n--ephemeral\n--skip-git-repo-check' ]]
grep -Fx -- "--add-dir" "$fake_args" >/dev/null
grep -Fx -- "${TMP_DIR}/extra-read" "$fake_args" >/dev/null
grep -Fx -- "${TMP_DIR}/extra-write" "$fake_args" >/dev/null
grep -F "Implement Phase 1 (Core Parser)" "$fake_stdin" >/dev/null

(
  cd "$REPO_DIR" &&
  COMMON_READ_FILES="" \
  PROVIDER=claude \
  ROOT_DIR="${TMP_DIR}/root" \
  RUN_VERIFICATION=0 \
  CLAUDE_BIN="$fake_claude" \
  CLAUDE_PERMISSION_MODE=acceptEdits \
  ADD_DIRS="${TMP_DIR}/extra-read ${TMP_DIR}/extra-write" \
  FAKE_ARGS="$fake_claude_args" \
  FAKE_STDIN="$fake_claude_stdin" \
  "$RUNNER" "$SPEC_FILE" 1
) >/dev/null

first_five_claude_args="$(sed -n '1,5p' "$fake_claude_args")"
[[ "$first_five_claude_args" == $'--print\n--model\nhaiku\n--permission-mode\nacceptEdits' ]]
grep -Fx -- "--no-session-persistence" "$fake_claude_args" >/dev/null
grep -Fx -- "--add-dir" "$fake_claude_args" >/dev/null
grep -Fx -- "${TMP_DIR}/extra-read" "$fake_claude_args" >/dev/null
grep -Fx -- "${TMP_DIR}/extra-write" "$fake_claude_args" >/dev/null
grep -F "Implement Phase 1 (Core Parser)" "$fake_claude_stdin" >/dev/null

mixed_codex="${TMP_DIR}/mixed-codex"
mixed_codex_args="${TMP_DIR}/mixed-codex-args"
mixed_codex_stdin="${TMP_DIR}/mixed-codex-stdin"
mixed_claude="${TMP_DIR}/mixed-claude"
mixed_claude_args="${TMP_DIR}/mixed-claude-args"
mixed_claude_stdin="${TMP_DIR}/mixed-claude-stdin"

cat > "$mixed_codex" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "$CODEX_FAKE_ARGS"
echo "-- invocation --" >> "$CODEX_FAKE_ARGS"
cat >> "$CODEX_FAKE_STDIN"
EOF
chmod +x "$mixed_codex"

cat > "$mixed_claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "$CLAUDE_FAKE_ARGS"
echo "-- invocation --" >> "$CLAUDE_FAKE_ARGS"
cat >> "$CLAUDE_FAKE_STDIN"
EOF
chmod +x "$mixed_claude"

(
  cd "$REPO_DIR" &&
  COMMON_READ_FILES="" \
  ROOT_DIR="${TMP_DIR}/root" \
  RUN_VERIFICATION=0 \
  PROVIDER=codex \
  CODEX_BIN="$mixed_codex" \
  CLAUDE_BIN="$mixed_claude" \
  MODEL_OVERRIDES="1:codex:gpt-5.4,2:claude:sonnet" \
  CODEX_FAKE_ARGS="$mixed_codex_args" \
  CODEX_FAKE_STDIN="$mixed_codex_stdin" \
  CLAUDE_FAKE_ARGS="$mixed_claude_args" \
  CLAUDE_FAKE_STDIN="$mixed_claude_stdin" \
  "$RUNNER" "$SPEC_FILE" all --from 1 --to 2
) >/dev/null

grep -F "gpt-5.4" "$mixed_codex_args" >/dev/null
grep -F "Implement Phase 1 (Core Parser)" "$mixed_codex_stdin" >/dev/null
grep -F "sonnet" "$mixed_claude_args" >/dev/null
grep -F "Implement Phase 2 (Report Writer)" "$mixed_claude_stdin" >/dev/null

mixed_list_output="$(
  cd "$REPO_DIR" &&
  MODEL_OVERRIDES="1:codex:gpt-5.4,2:claude:sonnet" spec2code "$SPEC_FILE" --list
)"
printf '%s\n' "$mixed_list_output" | grep -F $'Phase 1\tcodex\tgpt-5.4\tCore Parser' >/dev/null
printf '%s\n' "$mixed_list_output" | grep -F $'Phase 2\tclaude\tsonnet\tReport Writer' >/dev/null

echo "phase-10-final-verification: ok"
