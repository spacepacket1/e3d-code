#!/usr/bin/env bash
set -euo pipefail

# spec2code was renamed e3d-code. The old command, state dir and env var must keep working.
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NEW="$REPO_DIR/bin/e3d-code"
OLD="$REPO_DIR/bin/spec2code"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/e3d-code-phase15.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

[[ "$("$OLD" --version)" == "$("$NEW" --version)" ]] || fail "shim must report the same version"
ln -s "$OLD" "$TMP_DIR/spec2code-link"
[[ "$("$TMP_DIR/spec2code-link" --version)" == "$("$NEW" --version)" ]] || fail "shim must work through a symlink"

SPEC="$REPO_DIR/examples/feature-ticket.md"

# Fresh repo: state goes to .e3d-code
fresh="$TMP_DIR/fresh"; mkdir "$fresh"
(cd "$fresh" && "$NEW" "$SPEC" 1 --dry-run >/dev/null 2>&1) || true
[[ ! -d "$fresh/.spec2code" ]] || fail "fresh repo must not create .spec2code"

# Legacy repo with only .spec2code/: keep using it
legacy="$TMP_DIR/legacy"; mkdir -p "$legacy/.spec2code"
out="$(cd "$legacy" && "$NEW" "$SPEC" --preflight 2>&1 || true)"
[[ ! -d "$legacy/.e3d-code" ]] || fail "legacy repo with .spec2code must not get a second state dir"

# Old env var name still honored
grep -q 'S2C_CLAUDE_API_KEY_FILE' "$NEW" || fail "S2C_CLAUDE_API_KEY_FILE fallback missing"

echo "phase-15-rename-compat: ok"
