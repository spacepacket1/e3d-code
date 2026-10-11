# spec2code

Run Codex CLI or Claude CLI phase-by-phase from Markdown feature specs with model routing, shared context, and resumable execution.

Current version: `0.3.0`

`spec2code` turns a phased Markdown spec into separate provider runs. Each phase gets a fresh conversation, a focused prompt, and a model selected from conservative defaults or explicit overrides.

## Demo

Featured as an e3d-cast gallery sample:

<video src="https://cast.e3d.ai/samples/spec2code/video.mp4" controls width="720"></video>

[Watch the video](https://cast.e3d.ai/samples/spec2code/video.mp4)

## Why

Large implementation specs can waste context when every phase runs in one long conversation. This runner keeps each phase isolated so the selected provider starts with only the relevant spec section, the current working tree, and the files you tell it to read first.

## Requirements

- Bash
- `awk`, `grep`, `sort`
- Codex CLI and/or Claude CLI installed and authenticated for normal execution and `--preflight`

Check provider CLIs:

```bash
codex --help
claude --help
```

## Install

Clone the repo and add `bin` to your `PATH`:

```bash
git clone https://github.com/spacepacket1/spec2code.git
cd spec2code
export PATH="$PWD/bin:$PATH"
```

Or run it directly:

```bash
./bin/spec2code path/to/spec.md --list
```

## Spec Format

The spec should be Markdown with phase headings that include a phase number:

```md
## Phase 1 - Historical Replay
## Phase 2 - Walk-Forward Validation
## 6. Phase 3 - Execution Simulation
```

The runner extracts each phase section from its heading until the next phase heading.
Phase metadata is parsed once per runner process, sorted numerically, and duplicate phase numbers fail before the provider is launched.

## Usage

List phases with provider and model:

```bash
spec2code docs/feature-ticket.md --list
```

This prints provider and model per phase, for example:

```text
Phase 1  codex   gpt-5.4-mini  Core Parser
Phase 2  claude  sonnet        Report Writer
```

Print the installed runner version:

```bash
spec2code --version
```

Dry-run one phase status:

```bash
spec2code docs/feature-ticket.md 3 --dry-run
```

Print the full generated prompt for debugging:

```bash
spec2code docs/feature-ticket.md 3 --dry-run --verbose
```

Run one phase with Claude:

```bash
spec2code docs/feature-ticket.md 3 --provider claude
```

`--provider` sets the default provider for phases that do not have a mixed-provider override.

Run preflight checks only:

```bash
spec2code docs/feature-ticket.md --preflight
```

Prepare shared repo context only:

```bash
spec2code docs/feature-ticket.md --prepare-context
```

Run one phase:

```bash
spec2code docs/feature-ticket.md 3
```

Run all phases:

```bash
spec2code docs/feature-ticket.md all
```

Refresh shared repo context before execution:

```bash
spec2code docs/feature-ticket.md all --refresh-context
```

Resume from a phase after a rate limit or interruption:

```bash
spec2code docs/feature-ticket.md all --from 9
```

Run a bounded range:

```bash
spec2code docs/feature-ticket.md all --from 4 --to 8
```

Add files the provider should read first:

```bash
spec2code docs/feature-ticket.md 5 \
  --read package.json \
  --read pipeline.js \
  --read server.js
```

Recommended workflow for a new spec:

```bash
spec2code docs/feature-ticket.md --preflight
spec2code docs/feature-ticket.md --prepare-context
spec2code docs/feature-ticket.md all
```

Use `--refresh-context` when the repo changed enough that the shared context should be regenerated before execution.
Normal non-dry-run execution runs preflight automatically unless `SKIP_PREFLIGHT=1`; `--dry-run` remains usable without the provider installed.

## Runtime State

`.spec2code/` is runner runtime state. It is generated on demand and can contain:

- `context.md`: shared repo context used to reduce repeated setup across phases
- `manifest.tsv`: one tab-separated row per attempted phase run
- `summaries/phase-N.md`: lightweight per-phase summary placeholders

Shared context is generated automatically for both single-phase and `all` runs when `USE_SHARED_CONTEXT=1` and `context.md` does not already exist. It summarizes cheap local facts only: timestamp, root path, git status, top-level layout, detected package/config files, likely verification commands, and configured common read files.

Providers are asked to record a concise implementation handoff with changes, decisions, tests, and follow-ups. The runner preserves that handoff, adds independently observed verification results and a worktree snapshot, and includes up to three successful summaries in later phase prompts by default.

These generated files are safe to delete:

- `.spec2code/context.md`
- `.spec2code/manifest.tsv`
- `.spec2code/summaries/`

Deleting them removes runner history and cached context, but does not affect your source files.

## Spec Annotations

Specs can override a phase model, add extra read files, and include verification hints with HTML comments inside the phase body:

```md
## Phase 2 - Report Writer

<!-- runner:model=mini -->
<!-- runner:read=docs/reporting-notes.md -->
<!-- runner:verify=bash tests/reporting.sh -->
```

- `runner:model` overrides heuristic routing for that phase across providers
- `runner:read` adds files to the "Read first" block
- `runner:verify` tells the provider what to run and is rerun independently by the runner after a successful phase
- legacy `codex:*` annotations are still accepted; `codex:model` only applies when `PROVIDER=codex`

See [examples/feature-ticket.md](examples/feature-ticket.md) for a complete example.

## Model Routing

Default routing is intentionally conservative and tiered:

- `high` for architecture, security, migration, review/release, custody, routing, reconciliation, compliance, audit, and other high-risk phases
- `default` for most implementation phases
- `mini` for explicitly lightweight work

Provider defaults:

- Codex: `gpt-5.5`, `gpt-5.4`, `gpt-5.4-mini`
- Claude: `opus`, `sonnet`, `haiku`

`runner:model=high|default|mini` is the preferred provider-neutral form. Exact model names are still supported when you want provider-specific routing.

Override exact phase-to-model mapping:

```bash
MODEL_OVERRIDES="4:gpt-5.5,14:gpt-5.4-mini" \
  spec2code docs/feature-ticket.md all
```

Override exact phase-to-provider-and-model mapping:

```bash
MODEL_OVERRIDES="1:codex:gpt-5.4,2:claude:sonnet" \
  spec2code docs/feature-ticket.md all
```

Override default model names:

```bash
DEFAULT_MODEL=gpt-5.4 \
HIGH_MODEL=gpt-5.5 \
MINI_MODEL=gpt-5.4-mini \
  spec2code docs/feature-ticket.md --list
```

## Configuration

The runner invokes the selected provider like this:

```bash
PROVIDER=codex codex --ask-for-approval "$APPROVAL_POLICY" exec [--ephemeral] [--skip-git-repo-check] [--add-dir ...] --model "$model" --cd "$ROOT_DIR" --sandbox "$SANDBOX_MODE" -
PROVIDER=claude claude --print --model "$model" --permission-mode "$CLAUDE_PERMISSION_MODE" [--no-session-persistence] [--add-dir ...]
```

Environment overrides:

```bash
ROOT_DIR=/path/to/repo
STATE_DIR=/path/to/repo/.spec2code
CONTEXT_FILE=/path/to/repo/.spec2code/context.md
MANIFEST_FILE=/path/to/repo/.spec2code/manifest.tsv
SUMMARY_DIR=/path/to/repo/.spec2code/summaries
PROVIDER=codex
CODEX_BIN=codex
CLAUDE_BIN=claude
SKIP_PREFLIGHT=0
USE_SHARED_CONTEXT=1
USE_PHASE_SUMMARIES=1
SUMMARY_LOOKBACK=3
RUN_VERIFICATION=1
VERIFY_SHELL=bash
SANDBOX_MODE=workspace-write
APPROVAL_POLICY=on-request
MODE=exec
CODEX_EPHEMERAL=1
CODEX_SKIP_GIT_REPO_CHECK=0
CODEX_NETWORK_ACCESS=0
CLAUDE_PERMISSION_MODE=default
CLAUDE_NO_SESSION_PERSISTENCE=1
ADD_DIRS="/path/to/extra/repo /path/to/output"
DEFAULT_MODEL=<provider default>
HIGH_MODEL=<provider high>
MINI_MODEL=<provider mini>
MODEL_OVERRIDES="4:gpt-5.5,14:claude:sonnet"
COMMON_READ_FILES="package.json pipeline.js server.js"
```

- `STATE_DIR`, `CONTEXT_FILE`, `MANIFEST_FILE`, `SUMMARY_DIR`: runtime-state paths under `.spec2code/`
- `PROVIDER`: `codex` or `claude`
- `CODEX_BIN`, `CLAUDE_BIN`: provider CLI binary name or path
- `SKIP_PREFLIGHT`: set to `1` to skip automatic preflight on normal runs
- `USE_SHARED_CONTEXT`: set to `0` to omit `context.md` from prompts
- `USE_PHASE_SUMMARIES`: set to `0` to omit prior phase summaries from later prompts
- `SUMMARY_LOOKBACK`: number of previous successful summaries to include in a later phase prompt
- `RUN_VERIFICATION`: set to `0` to skip runner-managed verification after provider execution
- `VERIFY_SHELL`: shell used with `-lc` for verification commands
- `SANDBOX_MODE`, `APPROVAL_POLICY`, `MODE`: Codex-only execution settings
- `CODEX_EPHEMERAL`: set to `0` to let Codex persist phase sessions; default `1` avoids stale session persistence during runner-managed phase runs
- `CODEX_SKIP_GIT_REPO_CHECK`: set to `1` to pass `--skip-git-repo-check` to `codex exec`
- `CODEX_NETWORK_ACCESS`: set to `1` to pass `-c sandbox_workspace_write.network_access=true` to `codex exec`, enabling outbound network and inbound socket binds inside the `workspace-write` sandbox; default `0` keeps Codex's own network-disabled default. Needed for phases whose verification binds a listening socket (e.g. a local web-server test) — without it, `codex exec`'s sandbox denies the bind with `EPERM`.
- `CLAUDE_PERMISSION_MODE`: passed to `claude --permission-mode`
- `CLAUDE_NO_SESSION_PERSISTENCE`: set to `0` to let Claude persist phase sessions
- `ADD_DIRS`: space-separated directories to pass as repeated `--add-dir` flags to the selected provider
- `DEFAULT_MODEL`, `HIGH_MODEL`, `MINI_MODEL`: provider-specific default routed model names
- `MODEL_OVERRIDES`: exact `phase:model` or `phase:provider:model` mapping that beats heuristic routing and spec annotations
- `COMMON_READ_FILES`: space-separated files to include in every phase prompt when present

By default, runner output stays high level: current phase, provider, model, status, issues, and verification. Pass `--verbose` when you need full generated prompts or detailed provider output.

Manifest and summary behavior:

- `manifest.tsv` records each attempted phase run, including dry-runs and non-zero exits
- `summaries/phase-N.md` is updated after each attempt with the provider handoff, verification results, and current worktree snapshot
- later phases can read recent successful summaries in both single-phase and `all` runs unless `USE_PHASE_SUMMARIES=0`

When a phase has one or more `runner:verify` annotations, the commands run in declaration order and the first failure fails the phase and stops an `all` run. Without annotations, the runner conservatively infers one project-level check from common package files or shell tests. Verification is never executed during `--dry-run`.
Run only trusted specs: verification annotations are shell commands executed from `ROOT_DIR`.

## Safety Notes

The generated prompt tells the provider to:

- keep edits scoped to the current phase
- preserve existing behavior unless the phase requires a change
- avoid `node_modules`
- avoid later phases
- inspect the working tree when resuming after an interrupted run
- generate focused tests and run verification before finishing
- write a concise handoff for later phases

You should still review diffs after each phase.

## License

MIT
