#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="${REPO_DIR}/bin/e3d-code"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/e3d-code-phase14.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

bash -n "$RUNNER"

root="$TMP_DIR/root"
mkdir -p "$root"
trace="$TMP_DIR/trace.log"
: > "$trace"

spec="$TMP_DIR/spec.md"
cat > "$spec" <<'EOF'
# Auto-Route Test Spec

## Phase 1 - Rename A Button Label

Change the label on one button from "Submit" to "Send". Nothing else.

## Phase 2 - Rework Session Token Validation

Redesign concurrency and race condition handling in how session tokens are
validated and rotated.

## Phase 3 - Annotated Phase

<!-- runner:model=default -->

Neutral phase text with no keyword signal either way, but an explicit
annotation that must always beat auto-route.
EOF

# Fake codex: writes a canned tier to the file named by --output-last-message,
# and records one trace line per invocation so the test can assert call count.
fake_codex="$TMP_DIR/codex"
cat > "$fake_codex" <<EOF
#!/usr/bin/env bash
cat >/dev/null
printf 'codex-called\n' >> "$trace"
out=""
while [[ \$# -gt 0 ]]; do
  if [[ "\$1" == "--output-last-message" ]]; then
    out="\$2"
  fi
  shift
done
printf '%s' "\${FAKE_TIER:-high}" > "\$out"
EOF
chmod +x "$fake_codex"

# Phase 1 classified "mini" by the stub -- this doesn't match
# phase_model_tier()'s own keyword heuristic for this deliberately neutral
# text (which would fall through to "default"), so seeing "mini" here proves
# the LLM stub decided it, not the static grep.
out1="$(
  cd "$REPO_DIR" &&
  COMMON_READ_FILES="" ROOT_DIR="$root" CODEX_BIN="$fake_codex" FAKE_TIER=mini \
    AUTO_ROUTE_CACHE_FILE="$root/.e3d-code/route-cache.tsv" \
    "$RUNNER" "$spec" --list --auto-route
)"
printf '%s\n' "$out1" | grep -F $'Phase 1\tcodex\tgpt-5.4-mini\tRename A Button Label' >/dev/null || {
  echo "expected Phase 1 routed to mini tier, got:" >&2
  printf '%s\n' "$out1" >&2
  exit 1
}

# Explicit annotation on Phase 3 must still win over auto-route: codex is
# never invoked to classify it, and it resolves to the "default" tier exactly
# as the annotation says, regardless of FAKE_TIER.
printf '%s\n' "$out1" | grep -F $'Phase 3\tcodex\tgpt-5.4\tAnnotated Phase' >/dev/null || {
  echo "expected Phase 3's explicit annotation to win over auto-route, got:" >&2
  printf '%s\n' "$out1" >&2
  exit 1
}

calls_after_first="$(wc -l < "$trace" | tr -d ' ')"
(( calls_after_first == 2 )) || {
  echo "expected exactly 2 codex calls (phase 1 and 2, not phase 3), got $calls_after_first" >&2
  cat "$trace" >&2
  exit 1
}

# Re-running --list against the same spec/root must hit the cache: zero new
# codex invocations, same result.
: > "$trace"
out2="$(
  cd "$REPO_DIR" &&
  COMMON_READ_FILES="" ROOT_DIR="$root" CODEX_BIN="$fake_codex" FAKE_TIER=high \
    AUTO_ROUTE_CACHE_FILE="$root/.e3d-code/route-cache.tsv" \
    "$RUNNER" "$spec" --list --auto-route
)"
printf '%s\n' "$out2" | grep -F $'Phase 1\tcodex\tgpt-5.4-mini\tRename A Button Label' >/dev/null || {
  echo "expected cached mini result to persist despite FAKE_TIER=high, got:" >&2
  printf '%s\n' "$out2" >&2
  exit 1
}
calls_after_second="$(wc -l < "$trace" | tr -d ' ')"
(( calls_after_second == 0 )) || {
  echo "expected 0 codex calls on a cache hit, got $calls_after_second" >&2
  cat "$trace" >&2
  exit 1
}

# A classifier that returns garbage must fall back to the keyword heuristic
# (phase_model_tier) rather than failing the run.
fake_codex_bad="$TMP_DIR/codex-bad"
cat > "$fake_codex_bad" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
out=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--output-last-message" ]]; then
    out="$2"
  fi
  shift
done
printf 'I refuse to answer that.' > "$out"
EOF
chmod +x "$fake_codex_bad"

root_fallback="$TMP_DIR/root-fallback"
mkdir -p "$root_fallback"
out3="$(
  cd "$REPO_DIR" &&
  COMMON_READ_FILES="" ROOT_DIR="$root_fallback" CODEX_BIN="$fake_codex_bad" \
    "$RUNNER" "$spec" --list --auto-route 2>/tmp/e3d-code-phase14-stderr.txt
)"
# Phase 2's title/body hits phase_model_tier()'s own "concurrency"/"session"
# keyword path -> "high" is the correct fallback result here.
printf '%s\n' "$out3" | grep -F $'Phase 2\tcodex\tgpt-5.5\tRework Session Token Validation' >/dev/null || {
  echo "expected malformed classification to fall back to keyword heuristic, got:" >&2
  printf '%s\n' "$out3" >&2
  exit 1
}
grep -q "falling back to keyword heuristic" /tmp/e3d-code-phase14-stderr.txt || {
  echo "expected a fallback warning on stderr" >&2
  exit 1
}

echo 'phase-14-auto-route-tier: ok'
