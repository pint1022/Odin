#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

mkdir -p reports logs

run_agent() {
    local name="$1"
    local prompt_file="$2"

    echo "Starting ${name}..."

    codex \
        -s danger-full-access \
        -a never \
        exec \
        --ephemeral \
        --skip-git-repo-check \
        "$(cat "$prompt_file")" \
        >"logs/${name}.log" 2>&1
}

run_agent architect prompts/architect.md &
PID_ARCHITECT=$!

run_agent cli prompts/cli.md &
PID_CLI=$!

run_agent simulator prompts/simulator.md &
PID_SIMULATOR=$!

run_agent network prompts/network.md &
PID_NETWORK=$!

run_agent workload prompts/workload.md &
PID_WORKLOAD=$!

run_agent tester prompts/tester.md &
PID_TESTER=$!

wait "$PID_ARCHITECT"
wait "$PID_CLI"
wait "$PID_SIMULATOR"
wait "$PID_NETWORK"
wait "$PID_WORKLOAD"
wait "$PID_TESTER"

echo "Specialist analysis completed."

codex exec \
    --ephemeral \
    --sandbox workspace-write \
    --skip-git-repo-check \
    "$(cat prompts/manager.md)" \
    >logs/manager.log 2>&1

echo "Team analysis completed."
echo "Final report: reports/07-consolidated-report.md"
