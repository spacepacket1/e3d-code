#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="${REPO_DIR}/bin/e3d-code"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/e3d-code-phase13.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

bash -n "$RUNNER"

root="$TMP_DIR/root"
mkdir -p "$root"
trace="$TMP_DIR/trace.log"
: > "$trace"

spec="$TMP_DIR/spec.md"
cat > "$spec" <<'EOF'
# Mixed Provider Spec

## Phase 1 - Codex Phase

<!-- runner:model=codex:gpt-5.5 -->

Keep this phase scoped.

## Phase 2 - Claude Phase

<!-- runner:model=claude:sonnet -->

Keep this phase scoped.
EOF

fake_codex="$TMP_DIR/codex"
cat > "$fake_codex" <<EOF
#!/usr/bin/env bash
cat >/dev/null
printf 'codex-called\n' >> "$trace"
EOF
chmod +x "$fake_codex"

fake_claude="$TMP_DIR/claude"
cat > "$fake_claude" <<EOF
#!/usr/bin/env bash
cat >/dev/null
printf 'claude-called\n' >> "$trace"
EOF
chmod +x "$fake_claude"

# --list must resolve each phase's own annotated provider independently,
# before anything executes.
list_output="$(
  cd "$REPO_DIR" &&
  COMMON_READ_FILES="" ROOT_DIR="$root" "$RUNNER" "$spec" --list
)"
printf '%s\n' "$list_output" | grep -F $'Phase 1\tcodex\tgpt-5.5\tCodex Phase' >/dev/null
printf '%s\n' "$list_output" | grep -F $'Phase 2\tclaude\tsonnet\tClaude Phase' >/dev/null

# A single "all" run must dispatch phase 1 to codex and phase 2 to claude,
# in phase order, within the same invocation -- not one provider for the
# whole run.
(
  cd "$REPO_DIR" &&
  COMMON_READ_FILES="" ROOT_DIR="$root" RUN_VERIFICATION=0 \
    CODEX_BIN="$fake_codex" CODEX_SKIP_GIT_REPO_CHECK=1 \
    CLAUDE_BIN="$fake_claude" E3D_CODE_CLAUDE_API_KEY_FILE="$TMP_DIR/no-such-key-file" \
    "$RUNNER" "$spec" all
) >/dev/null

[[ "$(cat "$trace")" == $'codex-called\nclaude-called' ]] || {
  echo "expected codex then claude, got:" >&2
  cat "$trace" >&2
  exit 1
}

echo 'phase-13-mixed-provider-spec: ok'
