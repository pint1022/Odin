#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${SIMU_AI_TEAM_ROOT:-/home/xwang/dev/simu-ai-team}"
PROMPT_FILE="${PROJECT_PROMPT_FILE:-$ROOT/projects/proj1_baseline.md}"
LOG_DIR="${PROJECT_LOG_DIR:-$ROOT/logs}"
REPORT_DIR="${PROJECT_REPORT_DIR:-$ROOT/reports}"
CODEX_SANDBOX="${CODEX_SANDBOX:-danger-full-access}"
CODEX_APPROVAL="${CODEX_APPROVAL:-never}"
CODEX_BIN="${CODEX_BIN:-codex}"
TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"

die() { echo "ERROR: $*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
Usage:
  ./run_proj1.sh plan
  ./run_proj1.sh approve-task1
  ./run_proj1.sh prepare-task2
  ./run_proj1.sh custom "instruction"
  ./run_proj1.sh interactive

Environment overrides:
  SIMU_AI_TEAM_ROOT
  PROJECT_PROMPT_FILE
  PROJECT_LOG_DIR
  PROJECT_REPORT_DIR
  CODEX_BIN
  CODEX_SANDBOX       default: danger-full-access
  CODEX_APPROVAL      default: never
  CODEX_MODEL         optional
USAGE
}

preflight() {
  command -v "$CODEX_BIN" >/dev/null 2>&1 || die "Codex not found: $CODEX_BIN"
  [[ -d "$ROOT" ]] || die "Project root not found: $ROOT"
  [[ -f "$PROMPT_FILE" ]] || die "Prompt file not found: $PROMPT_FILE"
  [[ -d "$ROOT/workspace/aionnich/.git" ]] || die "AIONNICH repository not found"
  [[ -d "$ROOT/workspace/astra-sim-upstream/.git" ]] || die "ASTRA-sim repository not found"

  mkdir -p "$LOG_DIR" "$REPORT_DIR" "$ROOT/tmp"

  local branch
  branch="$(git -C "$ROOT/workspace/aionnich" branch --show-current)"
  [[ "$branch" == "master" ]] || die "AIONNICH must be on master; current: $branch"

  echo "Project root:      $ROOT"
  echo "Prompt:            $PROMPT_FILE"
  echo "Codex:             $($CODEX_BIN --version 2>/dev/null || true)"
  echo "Sandbox:           $CODEX_SANDBOX"
  echo "Approval policy:   $CODEX_APPROVAL"
  echo "AIONNICH commit:   $(git -C "$ROOT/workspace/aionnich" rev-parse HEAD)"
  echo "ASTRA-sim commit:  $(git -C "$ROOT/workspace/astra-sim-upstream" rev-parse HEAD)"

  if [[ -n "$(git -C "$ROOT/workspace/aionnich" status --short)" ]]; then
    echo "WARNING: AIONNICH working tree is not clean:" >&2
    git -C "$ROOT/workspace/aionnich" status --short >&2
  fi
}

run_codex() {
  local label="$1"
  local instruction="$2"
  local logfile="$LOG_DIR/${label}-${TIMESTAMP}.log"
  local args=(-s "$CODEX_SANDBOX" -a "$CODEX_APPROVAL")

  if [[ -n "${CODEX_MODEL:-}" ]]; then
    args+=(-m "$CODEX_MODEL")
  fi

  args+=(exec --ephemeral --skip-git-repo-check "$instruction")

  echo "Log: $logfile"
  (cd "$ROOT" && "$CODEX_BIN" "${args[@]}") 2>&1 | tee "$logfile"
}

plan_instruction() {
  cat <<EOF2
Read and follow the project prompt at:
$PROMPT_FILE

Begin only with Task 001 planning.
Verify both repositories, confirm AIONNICH is on master, record exact commits,
inspect build documentation, identify proposed build/test commands, and create
or update reports/tasks/task-001/plan.md.

Do not build yet. Do not modify either source repository. Do not begin Task 002.
End with: Task 001 is planned and awaiting your approval. I will not begin the build until you explicitly approve it.
EOF2
}

approve_task1_instruction() {
  cat <<EOF2
Read and follow the project prompt at:
$PROMPT_FILE

Task 001 is explicitly approved. Proceed with the approved build-baseline plan.
Build the unmodified AIONNICH master branch, run the approved baseline tests and
minimal example, record all commands/results under reports/tasks/task-001/,
verify neither source repository was modified, and present the completed Task 001 report.

Do not modify source code. Do not commit or push. Do not begin Task 002.
EOF2
}

prepare_task2_instruction() {
  cat <<EOF2
Read and follow the project prompt at:
$PROMPT_FILE

Task 001 is explicitly approved. Prepare Task 002 only; do not run a simulation.
For SX-TP8-PP1, locate the matching historical result, confirm GPT-22B,
Spectrum-X, 128 GPUs, DP=1, TP=8, PP=1, and the two-hour interpretation.
Present the exact command, effective configuration, historical-result source,
comparability, expected output location, and validation metrics. Stop for approval.

Do not run SX-TP8-PP1. Do not prepare later tests. Do not modify source code.
EOF2
}

main() {
  [[ $# -ge 1 ]] || { usage; exit 2; }
  local action="$1"; shift || true
  preflight

  case "$action" in
    plan) run_codex "proj1-plan" "$(plan_instruction)" ;;
    approve-task1) run_codex "task001-approved" "$(approve_task1_instruction)" ;;
    prepare-task2) run_codex "task002-prepare" "$(prepare_task2_instruction)" ;;
    custom)
      [[ $# -ge 1 ]] || die "custom requires an instruction"
      run_codex "custom" "$*"
      ;;
    interactive)
      cd "$ROOT"
      args=(-s "$CODEX_SANDBOX" -a "$CODEX_APPROVAL")
      [[ -n "${CODEX_MODEL:-}" ]] && args+=(-m "$CODEX_MODEL")
      exec "$CODEX_BIN" "${args[@]}"
      ;;
    help|-h|--help) usage ;;
    *) usage; die "Unknown action: $action" ;;
  esac
}

main "$@"
