#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="${REPO_DIR}/bin/e3d-code"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/e3d-code-phase12.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

bash -n "$RUNNER"

fake_claude="$TMP_DIR/claude"
cat > "$fake_claude" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
printf 'ANTHROPIC_API_KEY=%s\n' "${ANTHROPIC_API_KEY:-<unset>}"
EOF
chmod +x "$fake_claude"

key_file="$TMP_DIR/key-file"
cat > "$key_file" <<'EOF'
export ANTHROPIC_API_KEY="from-key-file-12345"
EOF

make_spec() {
  local spec="$1"
  cat > "$spec" <<'EOF'
# Temporary Spec

## Phase 1 - Claude Phase

Keep this phase scoped.
EOF
}

# No ANTHROPIC_API_KEY in the environment and the key file exists -> the
# runner should source it so the Claude call defaults to metered billing.
root1="$TMP_DIR/root1"
mkdir -p "$root1"
spec1="$TMP_DIR/spec1.md"
make_spec "$spec1"
out1="$(
  cd "$REPO_DIR" &&
  env -u ANTHROPIC_API_KEY \
    COMMON_READ_FILES="" ROOT_DIR="$root1" RUN_VERIFICATION=0 \
    CLAUDE_BIN="$fake_claude" E3D_CODE_CLAUDE_API_KEY_FILE="$key_file" \
    "$RUNNER" "$spec1" 1 --provider claude
)"
grep -F 'ANTHROPIC_API_KEY=from-key-file-12345' <<< "$out1" >/dev/null

# ANTHROPIC_API_KEY already set in the environment -> never overridden by
# the key file, even though the file exists and holds a different value.
root2="$TMP_DIR/root2"
mkdir -p "$root2"
spec2="$TMP_DIR/spec2.md"
make_spec "$spec2"
out2="$(
  cd "$REPO_DIR" &&
  COMMON_READ_FILES="" ROOT_DIR="$root2" RUN_VERIFICATION=0 \
    CLAUDE_BIN="$fake_claude" E3D_CODE_CLAUDE_API_KEY_FILE="$key_file" \
    ANTHROPIC_API_KEY="already-set-67890" \
    "$RUNNER" "$spec2" 1 --provider claude
)"
grep -F 'ANTHROPIC_API_KEY=already-set-67890' <<< "$out2" >/dev/null

echo 'phase-12-claude-api-key-default: ok'
