#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$REPO_DIR/bin/e3d-code"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/e3d-code-budget.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/root"
spec="$TMP_DIR/spec.md"
: > "$spec"
for phase in 1 2 3 4 5 6 7 8 9; do
  printf '## Phase %s - Guard fixture\n\nDo the bounded work.\n\n' "$phase" >> "$spec"
done

set +e
preflight="$(COMMON_READ_FILES="" ROOT_DIR="$TMP_DIR/root" MAX_PHASES_PER_RUN=8 \
  "$RUNNER" "$spec" all --preflight 2>&1)"
status=$?
set -e
[[ $status -ne 0 ]]
grep -F 'exceeds MAX_PHASES_PER_RUN=8' <<< "$preflight" >/dev/null

fake_codex="$TMP_DIR/codex"
cat > "$fake_codex" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
printf 'fixture response\n'
printf 'tokens used\n120001\n' >&2
EOF
chmod +x "$fake_codex"

set +e
phase_output="$(COMMON_READ_FILES="" ROOT_DIR="$TMP_DIR/root" RUN_VERIFICATION=0 \
  CODEX_BIN="$fake_codex" CODEX_SKIP_GIT_REPO_CHECK=1 \
  MAX_PROVIDER_TOKENS_PER_PHASE=120000 "$RUNNER" "$spec" 1 2>&1)"
status=$?
set -e
[[ $status -eq 75 ]]
grep -F 'exceeded provider token ceiling (120001 > 120000)' <<< "$phase_output" >/dev/null

echo 'phase-11-budget-guards: ok'
