#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PROJECT="$TMP/project"
mkdir -p \
    "$PROJECT/projects" \
    "$PROJECT/reports/tasks/task-001" \
    "$PROJECT/logs" \
    "$PROJECT/workspace/aionnich" \
    "$PROJECT/workspace/astra-sim-upstream"

printf 'Project test prompt\n' >"$PROJECT/projects/proj1_baseline.md"
printf 'complete\n' >"$PROJECT/reports/tasks/task-001/final-report.md"
printf 'next\n' >"$PROJECT/reports/tasks/task-001/plan.md"

git -C "$PROJECT/workspace/aionnich" init -q
git -C "$PROJECT/workspace/astra-sim-upstream" init -q

FAKE_CODEX="$TMP/fake-codex"
cat >"$FAKE_CODEX" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@"
printf '%s\n' "${FAKE_MARKER:?}"
EOF
chmod +x "$FAKE_CODEX"

run_runner() {
    local marker="$1"
    local output="$2"
    set +e
    FAKE_MARKER="$marker" \
    AIONNICH_PROJECT_ROOT="$PROJECT" \
    AIONNICH_MAX_TASKS=1 \
    AIONNICH_SLEEP_SECONDS=0 \
    CODEX_BIN="$FAKE_CODEX" \
        "$ROOT/continue_aionnich_auto.sh" >"$output" 2>&1
    RUN_STATUS=$?
    set -e
}

run_runner \
    "PROJECT_CONTINUE_NEXT_TASK: Task 002 still requires simulation" \
    "$TMP/continue.log"

if [[ "$RUN_STATUS" -eq 0 ]]; then
    echo "FAIL: marker templates in the echoed prompt caused false completion"
    exit 1
fi
if ! grep -Fq "Continuing automatically with: Task 002 still requires simulation" "$TMP/continue.log"; then
    echo "FAIL: the real continue marker was not honored"
    exit 1
fi
if grep -Fq "AIONNICH project final goal reached." "$TMP/continue.log"; then
    echo "FAIL: runner reported final completion for a continue marker"
    exit 1
fi

run_runner \
    "PROJECT_FINAL_GOAL_REACHED: simulations completed and validated" \
    "$TMP/final.log"

if [[ "$RUN_STATUS" -ne 0 ]]; then
    echo "FAIL: a real final marker did not complete the runner"
    exit 1
fi
if ! grep -Fq \
    "PROJECT_FINAL_GOAL_REACHED: simulations completed and validated" \
    "$TMP/final.log"; then
    echo "FAIL: final completion evidence was not reported"
    exit 1
fi

echo "PASS: autonomous runner distinguishes marker templates from real output"
