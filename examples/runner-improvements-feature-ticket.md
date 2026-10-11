# Feature Ticket: Shared Context and Faster Phase Execution

## Overview

Improve `spec2code` so fresh Codex sessions waste less context rediscovering the same repository facts, fail earlier on invalid setup, and leave behind useful execution records that make multi-phase work easier to resume and audit.

The implementation should preserve the existing command-line behavior unless a phase explicitly adds a new option. Existing usage from `README.md` should continue to work.

## Goals

- Reduce repeated token use across phase runs by generating reusable repo context.
- Make each Codex phase start with better, smaller, more consistent instructions.
- Avoid launching Codex when basic inputs or environment checks are invalid.
- Record enough run metadata to make interrupted multi-phase work easier to resume.
- Keep the runner dependency-light: Bash plus standard Unix tools already used by the project.

## Non-Goals

- Do not rewrite the runner in another language.
- Do not introduce external package dependencies.
- Do not call the OpenAI API directly from the script.
- Do not run multiple implementation phases in parallel.
- Do not change Codex CLI authentication or installation behavior.

## Existing Files

- `bin/spec2code`
- `README.md`
- `examples/feature-ticket.md`

## Shared Constraints

- Keep the script portable Bash.
- Keep changes scoped and readable; prefer small functions over a large control-flow rewrite.
- Preserve existing environment overrides unless this spec explicitly changes them.
- Generated runner state should live under `.spec2code/` inside `ROOT_DIR` by default.
- Do not commit generated state files unless documentation explicitly describes them as ignored runtime artifacts.
- Add focused shell-level verification where practical, using `--dry-run`, `--list`, or Bash syntax checks.

## Phase 1 - Runtime State Directory and Configuration

Add a small state-directory foundation that later phases can reuse.

### Requirements

- Introduce `STATE_DIR`, defaulting to `${ROOT_DIR}/.spec2code`.
- Introduce `CONTEXT_FILE`, defaulting to `${STATE_DIR}/context.md`.
- Introduce `MANIFEST_FILE`, defaulting to `${STATE_DIR}/manifest.tsv`.
- Ensure the state directory is created only when a command actually needs to write state.
- Do not create `.spec2code/` during `--help`, `--list`, or ordinary dry-run output unless a later phase explicitly requires it.
- Add a helper function for creating the state directory safely.
- Add state-related environment overrides to usage text and README documentation.

### Acceptance Criteria

- `bin/spec2code --help` documents the new environment variables.
- Existing `--list` behavior still works without creating runtime files.
- `bash -n bin/spec2code` passes.

## Phase 2 - Preflight Checks

Add an optional preflight check that validates the runner inputs and likely execution environment before launching Codex.

### Requirements

- Add a `--preflight` option that runs checks and exits without launching Codex.
- Add `SKIP_PREFLIGHT`, defaulting to `0`.
- For normal non-dry-run execution, run preflight automatically unless `SKIP_PREFLIGHT=1`.
- Preflight should validate:
  - `SPEC_FILE` exists.
  - `ROOT_DIR` exists and is a directory.
  - `CODEX_BIN` is available on `PATH` when it does not contain a slash.
  - `CODEX_BIN` is executable when it contains a slash.
  - selected target phases exist.
  - `--from` and `--to` are numeric and select at least one phase when target is `all`.
  - each configured `--read` file exists relative to `ROOT_DIR` or as an absolute path.
- Warnings are acceptable for missing common files from `COMMON_READ_FILES`; explicit `--read` files should be errors.
- Keep output human-readable and compact.

### Acceptance Criteria

- `spec2code examples/feature-ticket.md --preflight` reports success.
- Missing explicit `--read` files produce a non-zero exit.
- `--dry-run` does not require Codex CLI to be installed.
- Existing error messages for invalid targets remain clear.

## Phase 3 - Parse Spec Once Per Process

Reduce repeated `awk`/`sort` parsing by extracting phase metadata once and reusing it throughout the script.

### Requirements

- Replace repeated calls to `phase_lines` with a cached metadata representation.
- The cache may be a Bash array, temp file, or state-free process-local structure.
- Preserve the current supported heading formats:
  - `## Phase 1 - Title`
  - `## Phase 1 — Title`
  - `## 6. Phase 2 - Title`
- Detect duplicate phase numbers and fail with a clear error.
- Preserve numeric ordering for `all`, `--list`, `first_phase`, and `last_phase`.
- Keep `extract_phase_body` behavior compatible with current specs.

### Acceptance Criteria

- `spec2code examples/feature-ticket.md --list` produces the same phase ordering as before.
- Duplicate phase numbers in a temporary test spec fail before any Codex invocation.
- `bash -n bin/spec2code` passes.

## Phase 4 - Shared Repo Context Generation

Add a reusable repo briefing that each phase can read before implementation.

### Requirements

- Add `--prepare-context`, which writes `CONTEXT_FILE` and exits.
- Add `--refresh-context`, which regenerates the context before executing selected phases.
- Add `USE_SHARED_CONTEXT`, defaulting to `1`.
- When `USE_SHARED_CONTEXT=1` and the context file exists, include it in the generated phase prompt.
- Do not auto-generate context during ordinary single-phase runs unless `--refresh-context` or `--prepare-context` is provided.
- For `all` runs, generate context automatically at the beginning when `USE_SHARED_CONTEXT=1` and `CONTEXT_FILE` does not exist.
- The generated context should include:
  - timestamp
  - root directory
  - current git branch when available
  - current git status summary
  - top-level file and directory layout
  - detected package/config files
  - likely test or verification commands inferred from known files
  - files configured through `COMMON_READ_FILES`
- Keep the context generator conservative. It should summarize local filesystem facts, not infer architecture beyond what it can cheaply detect.

### Acceptance Criteria

- `spec2code examples/feature-ticket.md --prepare-context` creates `.spec2code/context.md`.
- A dry-run after context creation includes the context file in the "Start by reading" block.
- `USE_SHARED_CONTEXT=0` omits the context file from prompts.
- Context generation should not fail merely because the directory is not a git repo.

## Phase 5 - Prompt Compaction

Make per-phase prompts shorter while retaining the instructions that matter most.

### Requirements

- Refactor `phase_prompt` so repeated instructions are concise and grouped.
- Avoid duplicate statements such as both "Keep changes scoped" and "Do not implement later phases" appearing multiple times.
- Include the shared context file in the read list when enabled and present.
- Keep the full relevant phase body in the prompt.
- Preserve the resume instruction, but shorten it.
- Make the generated dry-run prompt easy to scan.

### Acceptance Criteria

- `spec2code examples/feature-ticket.md 1 --dry-run` still clearly tells Codex:
  - which phase to implement
  - which spec file the phase came from
  - which files to read first
  - to preserve scope and behavior
  - to run verification
- The prompt is meaningfully shorter than the previous version for the example spec.

## Phase 6 - Phase Run Manifest

Record phase execution metadata so interrupted runs are easier to inspect.

### Requirements

- Append one manifest row per attempted phase execution.
- Use a simple tab-separated format suitable for shell tools.
- Include at least:
  - timestamp
  - spec file
  - phase number
  - phase title
  - selected model
  - mode
  - dry-run flag
  - exit status
- Ensure the state directory is created before writing the manifest.
- Make manifest writing best-effort but visible: if writing fails, print a warning without masking the Codex exit status.
- Do not write manifest rows for `--help`, `--list`, or `--preflight`.
- For `--dry-run`, record the dry-run attempt after printing the prompt.

### Acceptance Criteria

- Running one dry-run phase appends a manifest row with `dry-run` marked.
- Running `all --dry-run` appends one row per selected phase.
- A failed Codex invocation records a non-zero exit status.

## Phase 7 - Phase Completion Summaries

Create lightweight per-phase summary placeholders that future phases can read.

### Requirements

- Add `SUMMARY_DIR`, defaulting to `${STATE_DIR}/summaries`.
- After each phase attempt, write or update `phase-N.md` in `SUMMARY_DIR`.
- The summary should include:
  - phase number and title
  - selected model
  - completion timestamp
  - exit status
  - a placeholder section for human notes
- Do not claim what Codex changed unless the runner can determine it cheaply and accurately.
- Include previous successful summary files in the "Start by reading" block for later phases when target is `all`.
- Limit summary inclusion so prompts do not grow without bound:
  - include at most the immediately previous phase summary by default
  - add `SUMMARY_LOOKBACK`, defaulting to `1`
- Allow disabling summary prompt inclusion with `USE_PHASE_SUMMARIES=0`.

### Acceptance Criteria

- After `all --dry-run`, summary files exist for each selected phase.
- Phase 2 dry-run prompt includes the Phase 1 summary when summaries are enabled.
- `SUMMARY_LOOKBACK=0` disables prior-summary prompt inclusion.

## Phase 8 - Spec Metadata Annotations

Allow specs to override model, read files, and verification hints per phase using simple HTML comments.

### Requirements

- Support phase-local annotations inside a phase body:
  - `<!-- codex:model=gpt-5.5 -->`
  - `<!-- codex:read=path/to/file -->`
  - `<!-- codex:verify=npm test -->`
- Multiple `codex:read` annotations should be allowed.
- Phase annotation model should take precedence over heuristic model routing.
- `MODEL_OVERRIDES` should take precedence over spec annotations.
- Annotated read files should be included in the "Start by reading" block for that phase.
- Verification hints should appear in the prompt, but the runner does not need to execute them itself.
- Unknown annotations should be ignored.

### Acceptance Criteria

- A temporary spec with `<!-- codex:model=gpt-5.4-mini -->` lists that model for the phase.
- `MODEL_OVERRIDES` still wins over the annotation.
- Dry-run output includes annotated read files and verification hints.

## Phase 9 - Documentation and Examples

Update the public documentation so users can adopt the new workflow without reading the script.

### Requirements

- Update `README.md` with:
  - shared context overview
  - preflight usage
  - manifest and summary file behavior
  - spec annotation examples
  - environment variable reference for new options
- Add or update an example spec demonstrating:
  - phase headings
  - model annotation
  - read annotation
  - verification annotation
- Document which generated files are safe to delete.
- Keep the README concise; avoid turning it into an exhaustive manual.

### Acceptance Criteria

- README examples use the actual command name `spec2code`.
- A new user can understand the recommended `--preflight`, `--prepare-context`, and `all` flow.
- Documentation makes clear that `.spec2code/` is runtime state.

## Phase 10 - Ignore Runtime State and Final Verification

Make generated runtime state safe by default and verify the completed workflow.

### Requirements

- Add `.spec2code/` to `.gitignore`.
- If the repo does not have `.gitignore`, create one with only the required runtime-state entry.
- Run shell syntax verification.
- Run representative command checks:
  - `spec2code examples/feature-ticket.md --list`
  - `spec2code examples/feature-ticket.md --preflight`
  - `spec2code examples/feature-ticket.md 1 --dry-run`
  - `spec2code examples/feature-ticket.md all --dry-run`
- Do not require actual Codex execution for final verification.

### Acceptance Criteria

- Runtime state is ignored by git.
- All representative non-Codex checks pass.
- Existing basic usage remains backward compatible.

