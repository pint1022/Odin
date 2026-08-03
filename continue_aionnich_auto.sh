#!/usr/bin/env bash
#
# continue_aionnich_auto.sh
#
# Autonomous AIONNICH task runner.
# It continues through prepared tasks, fixes locally resolvable failures,
# and stops only when the final project goal is reached, an external blocker
# requires human action, or a configured safety limit is reached.
#
# Usage:
#   ./continue_aionnich_auto.sh
#   ./continue_aionnich_auto.sh --max-tasks 20
#   ./continue_aionnich_auto.sh --start-task "Task 002"
#
set -Eeuo pipefail

ROOT="${AIONNICH_PROJECT_ROOT:-/home/xwang/dev/simu-ai-team}"
PROMPT_FILE="${AIONNICH_PROMPT_FILE:-$ROOT/projects/proj1_baseline.md}"
REPORT_ROOT="${AIONNICH_REPORT_ROOT:-$ROOT/reports/tasks}"
LOG_DIR="${AIONNICH_LOG_DIR:-$ROOT/logs}"
STATE_DIR="${AIONNICH_STATE_DIR:-$ROOT/.aionnich-runner}"

CODEX_BIN="${CODEX_BIN:-codex}"
CODEX_SANDBOX="${CODEX_SANDBOX:-danger-full-access}"
CODEX_APPROVAL="${CODEX_APPROVAL:-never}"
CODEX_MODEL="${CODEX_MODEL:-}"

MAX_TASKS="${AIONNICH_MAX_TASKS:-25}"
MAX_NO_PROGRESS="${AIONNICH_MAX_NO_PROGRESS:-3}"
START_TASK=""
SLEEP_BETWEEN_RUNS="${AIONNICH_SLEEP_SECONDS:-2}"

FINAL_MARKER="PROJECT_FINAL_GOAL_REACHED"
BLOCKER_MARKER="PROJECT_EXTERNAL_BLOCKER"
CONTINUE_MARKER="PROJECT_CONTINUE_NEXT_TASK"

usage() {
    cat <<'EOF'
Usage:
  ./continue_aionnich_auto.sh
  ./continue_aionnich_auto.sh --max-tasks 20
  ./continue_aionnich_auto.sh --start-task "Task 002"

Environment overrides:
  AIONNICH_PROJECT_ROOT
  AIONNICH_PROMPT_FILE
  AIONNICH_REPORT_ROOT
  AIONNICH_LOG_DIR
  AIONNICH_STATE_DIR
  AIONNICH_MAX_TASKS
  AIONNICH_MAX_NO_PROGRESS
  AIONNICH_SLEEP_SECONDS
  CODEX_BIN
  CODEX_SANDBOX
  CODEX_APPROVAL
  CODEX_MODEL
EOF
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --max-tasks)
            [[ $# -ge 2 ]] || die "--max-tasks requires a number"
            MAX_TASKS="$2"
            shift 2
            ;;
        --start-task)
            [[ $# -ge 2 ]] || die "--start-task requires a task name"
            START_TASK="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            die "Unknown argument: $1"
            ;;
    esac
done

[[ "$MAX_TASKS" =~ ^[1-9][0-9]*$ ]] || die "MAX_TASKS must be a positive integer"
[[ "$MAX_NO_PROGRESS" =~ ^[1-9][0-9]*$ ]] || die "MAX_NO_PROGRESS must be a positive integer"

command -v "$CODEX_BIN" >/dev/null 2>&1 ||
    die "Codex executable not found: $CODEX_BIN"

[[ -d "$ROOT" ]] || die "Project root not found: $ROOT"
[[ -f "$PROMPT_FILE" ]] || die "Project prompt not found: $PROMPT_FILE"
[[ -d "$ROOT/workspace/aionnich/.git" ]] ||
    die "AIONNICH repository missing: $ROOT/workspace/aionnich"
[[ -d "$ROOT/workspace/astra-sim-upstream/.git" ]] ||
    die "ASTRA-sim repository missing: $ROOT/workspace/astra-sim-upstream"

mkdir -p "$LOG_DIR" "$REPORT_ROOT" "$STATE_DIR"

branch="$(git -C "$ROOT/workspace/aionnich" branch --show-current)"
[[ "$branch" == "master" ]] ||
    die "AIONNICH must be on master; current branch: $branch"

latest_file() {
    local filename="$1"
    find "$REPORT_ROOT" -type f -name "$filename" -printf '%T@ %p\n' 2>/dev/null |
        sort -nr |
        awk 'NR==1 {sub(/^[^ ]+ /, ""); print; exit}'
}

snapshot_state() {
    {
        echo "aionnich_commit=$(git -C "$ROOT/workspace/aionnich" rev-parse HEAD)"
        echo "aionnich_status_hash=$(git -C "$ROOT/workspace/aionnich" status --porcelain=v1 | sha256sum | awk '{print $1}')"
        echo "astra_commit=$(git -C "$ROOT/workspace/astra-sim-upstream" rev-parse HEAD)"
        echo "latest_report=$(latest_file final-report.md || true)"
        echo "latest_plan=$(latest_file plan.md || true)"
        find "$REPORT_ROOT" -type f -printf '%P %s %T@\n' 2>/dev/null | sort | sha256sum
    } | sha256sum | awk '{print $1}'
}

run_codex_iteration() {
    local iteration="$1"
    local current_task="$2"
    local latest_report latest_plan timestamp logfile instruction

    latest_report="$(latest_file final-report.md || true)"
    latest_plan="$(latest_file plan.md || true)"
    timestamp="$(date '+%Y%m%d-%H%M%S')"
    logfile="$LOG_DIR/aionnich-auto-${iteration}-${timestamp}.log"

    instruction=$(cat <<EOF
Read and obey the complete AIONNICH project prompt:

$PROMPT_FILE

You are running autonomous project iteration $iteration.

Current approved task:
$current_task

Latest completed task report:
${latest_report:-No completed report found. Inspect the project state and begin from the earliest incomplete approved task.}

Latest prepared task plan:
${latest_plan:-No prepared plan found. Create the required plan as part of the current task, then execute it.}

AUTONOMOUS EXECUTION RULES:

1. Execute the current task and every subtask required by the project prompt.
2. Fix all locally resolvable bugs encountered in build, configuration, CLI, workload generation, ns-3 integration, simulation execution, result parsing, and historical-result comparison.
3. Do not stop after an intermediate failure. Reproduce, isolate, fix, rebuild, and retest until the current task's acceptance criteria pass.
4. Use valid configurations available in the AIONNICH repository. Prefer the requested GPT-22B, Spectrum-X, POD512, 128-GPU configurations when supported.
5. If comparable historical results exist, compare against them and investigate material differences.
6. If no comparable historical result exists, run the valid simulation and establish a fully documented new baseline. Absence of historical data is not a blocker.
7. Run simulations sequentially. Fully validate each result before proceeding.
8. You are authorized to continue to the next numbered task automatically after the current task passes.
9. Keep workspace/astra-sim-upstream read-only.
10. Keep AIONNICH on branch master.
11. Do not commit, push, merge, or open a pull/merge request.
12. Record every command, source change, failure, root cause, build, test, simulation, comparison, and result under reports/tasks/.
13. Continue through subsequent tasks until the final project goal defined in the prompt is achieved.
14. Stop only when:
    a. The final project goal is fully achieved and validated;
    b. A genuine external blocker requires credentials, unavailable hardware, inaccessible data/service, or a user-only design decision;
    c. Continuing would require an unapproved destructive action, commit, push, or modification of ASTRA-sim.

At the very end of this iteration, print exactly one of these marker lines:

$FINAL_MARKER: <brief evidence that all final acceptance criteria passed>

$BLOCKER_MARKER: <exact external blocker and required human action>

$CONTINUE_MARKER: <next task name and why another Codex iteration is required>

Do not use the final-goal marker unless the complete project—not merely the current task—has passed all final acceptance criteria.
EOF
)

    local args=(-s "$CODEX_SANDBOX" -a "$CODEX_APPROVAL")
    [[ -n "$CODEX_MODEL" ]] && args+=(-m "$CODEX_MODEL")
    args+=(exec --ephemeral --skip-git-repo-check "$instruction")

    echo "============================================================"
    echo "Iteration:       $iteration"
    echo "Current task:    $current_task"
    echo "Log:             $logfile"
    echo "AIONNICH commit: $(git -C "$ROOT/workspace/aionnich" rev-parse --short HEAD)"
    echo "============================================================"

    (
        cd "$ROOT"
        "$CODEX_BIN" "${args[@]}"
    ) 2>&1 | tee "$logfile"

    LAST_LOGFILE="$logfile"
}

extract_next_task() {
    local logfile="$1"
    local line
    line="$(
        awk -v marker="$CONTINUE_MARKER: " '
            index($0, marker) == 1 && substr($0, length(marker) + 1, 1) != "<" {
                line = $0
            }
            END {
                if (line != "") {
                    print line
                }
            }
        ' "$logfile"
    )"
    if [[ -n "$line" ]]; then
        printf '%s\n' "${line#*$CONTINUE_MARKER: }"
    else
        printf '%s\n' "Continue the earliest incomplete task in the project reports"
    fi
}

extract_last_control_marker() {
    local logfile="$1"
    awk \
        -v final="$FINAL_MARKER: " \
        -v blocker="$BLOCKER_MARKER: " \
        -v continue_marker="$CONTINUE_MARKER: " '
        {
            marker = ""
            if (index($0, final) == 1) {
                marker = final
            } else if (index($0, blocker) == 1) {
                marker = blocker
            } else if (index($0, continue_marker) == 1) {
                marker = continue_marker
            }

            if (marker != "" && substr($0, length(marker) + 1, 1) != "<") {
                line = $0
            }
        }
        END {
            if (line != "") {
                print line
            }
        }
    ' "$logfile"
}

current_task="${START_TASK:-Continue from the latest project state}"
previous_state="$(snapshot_state)"
no_progress_count=0

for ((iteration=1; iteration<=MAX_TASKS; iteration++)); do
    run_codex_iteration "$iteration" "$current_task"

    control_marker="$(extract_last_control_marker "$LAST_LOGFILE")"

    if [[ "$control_marker" == "$FINAL_MARKER: "* ]]; then
        echo
        echo "AIONNICH project final goal reached."
        printf '%s\n' "$control_marker"
        exit 0
    fi

    if [[ "$control_marker" == "$BLOCKER_MARKER: "* ]]; then
        echo
        echo "AIONNICH project stopped on an external blocker."
        printf '%s\n' "$control_marker"
        exit 2
    fi

    new_state="$(snapshot_state)"
    if [[ "$new_state" == "$previous_state" ]]; then
        no_progress_count=$((no_progress_count + 1))
        echo "WARNING: no measurable repository/report progress in iteration $iteration ($no_progress_count/$MAX_NO_PROGRESS)." >&2
    else
        no_progress_count=0
    fi

    if (( no_progress_count >= MAX_NO_PROGRESS )); then
        echo "ERROR: stopping after $MAX_NO_PROGRESS consecutive iterations without measurable progress." >&2
        echo "Review: $LAST_LOGFILE" >&2
        exit 3
    fi

    previous_state="$new_state"
    current_task="$(extract_next_task "$LAST_LOGFILE")"

    echo
    echo "Continuing automatically with: $current_task"
    sleep "$SLEEP_BETWEEN_RUNS"
done

echo "ERROR: reached safety limit of $MAX_TASKS Codex iterations before final completion." >&2
exit 4
