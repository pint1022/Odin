#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${AIONNICH_PROJECT_ROOT:-/home/xwang/dev/simu-ai-team}"
PROMPT_FILE="${AIONNICH_PROMPT_FILE:-$ROOT/projects/proj1_baseline.md}"
REPORT_ROOT="${AIONNICH_REPORT_ROOT:-$ROOT/reports/tasks}"
LOG_DIR="${AIONNICH_LOG_DIR:-$ROOT/logs}"

CODEX_BIN="${CODEX_BIN:-codex}"
CODEX_SANDBOX="${CODEX_SANDBOX:-danger-full-access}"
CODEX_APPROVAL="${CODEX_APPROVAL:-never}"
CODEX_MODEL="${CODEX_MODEL:-}"

AUTO_APPROVE=0
TASK_OVERRIDE=""

usage() {
cat <<'EOF'
Usage:
  ./continue_aionnich_next.sh
  ./continue_aionnich_next.sh --yes
  ./continue_aionnich_next.sh --task "Task 003"
EOF
}

die() { echo "ERROR: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes|-y) AUTO_APPROVE=1; shift ;;
    --task) [[ $# -ge 2 ]] || die "--task requires a value"; TASK_OVERRIDE="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

command -v "$CODEX_BIN" >/dev/null 2>&1 || die "Codex not found"
[[ -d "$ROOT" ]] || die "Project root not found: $ROOT"
[[ -f "$PROMPT_FILE" ]] || die "Prompt not found: $PROMPT_FILE"
[[ -d "$ROOT/workspace/aionnich/.git" ]] || die "Missing AIONNICH repo"
[[ -d "$ROOT/workspace/astra-sim-upstream/.git" ]] || die "Missing ASTRA-sim repo"

mkdir -p "$LOG_DIR" "$REPORT_ROOT"

branch="$(git -C "$ROOT/workspace/aionnich" branch --show-current)"
[[ "$branch" == "master" ]] || die "AIONNICH must be on master; current: $branch"

latest_report="$(find "$REPORT_ROOT" -type f -name final-report.md -printf '%T@ %p\n' 2>/dev/null | sort -nr | awk 'NR==1 {sub(/^[^ ]+ /, ""); print; exit}')"
latest_plan="$(find "$REPORT_ROOT" -type f -name plan.md -printf '%T@ %p\n' 2>/dev/null | sort -nr | awk 'NR==1 {sub(/^[^ ]+ /, ""); print; exit}')"

[[ -n "$latest_report" ]] || die "No final-report.md found"
[[ -n "$latest_plan" ]] || die "No plan.md found"

approved_task="${TASK_OVERRIDE:-the latest prepared next task}"

echo "Latest report: $latest_report"
echo "Latest plan:   $latest_plan"

if [[ "$AUTO_APPROVE" -ne 1 ]]; then
  read -r -p "Approve and run ${approved_task}? [y/N] " answer
  case "$answer" in
    y|Y|yes|YES) ;;
    *) echo "Not approved. No task started."; exit 0 ;;
  esac
fi

timestamp="$(date '+%Y%m%d-%H%M%S')"
logfile="$LOG_DIR/aionnich-next-task-$timestamp.log"

instruction=$(cat <<EOF
Read and follow:
$PROMPT_FILE

The following task is explicitly approved:
$approved_task

Latest completed task report:
$latest_report

Latest prepared task plan:
$latest_plan

Execute only the approved next task. Complete every subtask successfully. Debug all locally resolvable failures. Record all commands, changes, builds, tests, simulations, comparisons, and root causes. Keep AIONNICH on master. Treat ASTRA-sim as read-only. Do not commit or push. After completion, prepare the following task plan but do not execute it. Stop for my review.
EOF
)

args=(-s "$CODEX_SANDBOX" -a "$CODEX_APPROVAL")
[[ -n "$CODEX_MODEL" ]] && args+=(-m "$CODEX_MODEL")
args+=(exec --ephemeral --skip-git-repo-check "$instruction")

cd "$ROOT"
"$CODEX_BIN" "${args[@]}" 2>&1 | tee "$logfile"
