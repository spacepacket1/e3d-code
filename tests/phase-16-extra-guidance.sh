#!/usr/bin/env bash
set -euo pipefail

# E3D_CODE_EXTRA_GUIDANCE_FILE appends guidance after the guardrails; it never replaces them.
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$REPO_DIR/bin/e3d-code"
SPEC="$REPO_DIR/examples/feature-ticket.md"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/e3d-code-phase16.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

cd "$TMP_DIR"
base="$("$BIN" "$SPEC" 1 --dry-run --verbose 2>&1)" || fail "baseline dry-run failed"
[[ "$base" == *"Guardrails:"* ]] || fail "baseline prompt must show guardrails"
[[ "$base" != *"Additional guidance"* ]] || fail "no extra guidance expected when unset"

printf 'Prefer small commits.\n' > "$TMP_DIR/extra.md"
out="$(E3D_CODE_EXTRA_GUIDANCE_FILE="$TMP_DIR/extra.md" "$BIN" "$SPEC" 1 --dry-run --verbose 2>&1)" || fail "dry-run with guidance failed"
[[ "$out" == *"Prefer small commits."* ]] || fail "extra guidance missing"
[[ "$out" == *"Do not touch node_modules."* ]] || fail "guardrails must remain when guidance is set"
g="${out%%Additional guidance*}"; [[ "$g" == *"Guardrails:"* ]] || fail "guidance must come after guardrails"

if E3D_CODE_EXTRA_GUIDANCE_FILE="$TMP_DIR/missing.md" "$BIN" "$SPEC" 1 --dry-run --verbose >/dev/null 2>&1; then
  fail "unreadable guidance file must fail loudly"
fi
echo "phase-16-extra-guidance: ok"
