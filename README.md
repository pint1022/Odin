# Simu AI Team

This workspace coordinates analysis, builds, tests, and simulation campaigns for
AIONNICH and upstream ASTRA-sim. The source repositories are nested under
`workspace/` and are intentionally managed separately from this orchestration
workspace.

## Prerequisites

- Bash and Git
- Cursor CLI/Codex available as `codex`
- AIONNICH at `workspace/aionnich`
- ASTRA-sim at `workspace/astra-sim-upstream`
- AIONNICH checked out on `master`

Most runners use `danger-full-access` with approval mode `never`. Review the
project prompt and prepared task plan before launching them. The scripts do not
commit or push source changes.

## Workspace setup

Run these commands from the repository root:

```bash
bash setup_repo.sh
bash check_workspace.sh
```

`setup_repo.sh` finds nested Git repositories, backs up `.gitignore` as
`.gitignore.backup`, and adds exclusions for the nested repositories.
`check_workspace.sh` fails if either external source repository is staged in the
outer repository.

If the two source repositories were accidentally staged, run:

```bash
bash remove_workspace_data.sh
```

Despite its name, this script does not delete the repositories. It adds their
paths to `.gitignore` and removes them from the outer Git staging area.

## Project runners

### Run the original specialist team

```bash
./run-team.sh
```

This starts the architect, CLI, simulator, network, workload, and test agents in
parallel. After all specialists finish, the program manager consolidates their
reports into `reports/07-consolidated-report.md`. Agent output is written under
`logs/`.

### Run Project 1 actions

```bash
./run_proj1.sh plan
./run_proj1.sh approve-task1
./run_proj1.sh prepare-task2
./run_proj1.sh custom "instruction"
./run_proj1.sh interactive
```

- `plan` prepares Task 001 without building.
- `approve-task1` executes the approved Task 001 build baseline.
- `prepare-task2` prepares the first simulation configuration without running it.
- `custom` runs one supplied project instruction.
- `interactive` opens an interactive Codex session in the project root.

The runner validates repository locations, requires AIONNICH `master`, reports
both source revisions, and warns if the AIONNICH working tree is dirty.

### Run one approved next task

```bash
./continue_aionnich_next.sh
./continue_aionnich_next.sh --yes
./continue_aionnich_next.sh --task "Task 002"
```

Without `--yes`, the script asks for approval. It selects the newest task plan
and final report, executes only the approved task, prepares the following task,
and stops for review.

### Continue autonomously

```bash
./continue_aionnich_auto.sh
./continue_aionnich_auto.sh --max-tasks 20
./continue_aionnich_auto.sh --start-task "Task 002"
```

The autonomous runner repeatedly invokes Codex, fixes locally resolvable
problems, runs simulations sequentially, records evidence under
`reports/tasks/`, and follows control markers emitted by each iteration:

- `PROJECT_CONTINUE_NEXT_TASK` starts another iteration.
- `PROJECT_EXTERNAL_BLOCKER` stops with exit code 2 for a required user decision
  or unavailable external resource.
- `PROJECT_FINAL_GOAL_REACHED` stops successfully only after final validation.

It also stops with exit code 3 after the configured number of no-progress
iterations, or exit code 4 after reaching the task-iteration safety limit.

To resume after a blocker, first record the required decision in the relevant
task plan or project prompt, then run:

```bash
./continue_aionnich_auto.sh --start-task "Task 002"
```

For example, a simulation-duration decision must explicitly state whether the
campaign uses simulated time, a wall-clock timeout, or a reduced validation
duration, and whether missing historical results become new baselines.

## Configuration overrides

`run_proj1.sh` supports:

```bash
SIMU_AI_TEAM_ROOT=/path/to/simu-ai-team
PROJECT_PROMPT_FILE=/path/to/prompt.md
PROJECT_LOG_DIR=/path/to/logs
PROJECT_REPORT_DIR=/path/to/reports
CODEX_BIN=codex
CODEX_SANDBOX=danger-full-access
CODEX_APPROVAL=never
CODEX_MODEL=model-name
```

The continuation runners use the equivalent `AIONNICH_*` variables:

```bash
AIONNICH_PROJECT_ROOT=/path/to/simu-ai-team
AIONNICH_PROMPT_FILE=/path/to/prompt.md
AIONNICH_REPORT_ROOT=/path/to/task-reports
AIONNICH_LOG_DIR=/path/to/logs
```

The autonomous runner additionally accepts:

```bash
AIONNICH_STATE_DIR=/path/to/state
AIONNICH_MAX_TASKS=25
AIONNICH_MAX_NO_PROGRESS=3
AIONNICH_SLEEP_SECONDS=2
```

## Tests

Run the orchestration regression test with:

```bash
bash tests/test_continue_aionnich_auto_markers.sh
```

The test verifies that control-marker examples echoed from a prompt cannot be
mistaken for a real completion marker.

## Outputs and safety

- Project task records: `reports/tasks/task-NNN/`
- Consolidated analysis: `reports/`
- Agent and runner logs: `logs/`
- Autonomous runner state: `.aionnich-runner/`
- External repositories: `workspace/aionnich/` and
  `workspace/astra-sim-upstream/`

Treat `workspace/astra-sim-upstream` as read-only. Simulation runs can be
CPU-, memory-, and time-intensive; use bounded timeouts, unique result
directories, and sequential execution unless a reviewed plan explicitly allows
otherwise.
