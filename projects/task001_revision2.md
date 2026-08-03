# Task 002: Available-Configuration Simulation Validation

## Objective

Run AIONNICH simulations using the valid model, topology, network, and parallelism configurations currently available in the repository.

When corresponding historical results exist and are sufficiently comparable, compare the new results with them.

When no matching historical result exists, run the simulation normally and record the result as a new baseline.

Task 002 must not be blocked solely because historical results are unavailable.

---

# Operating Principles

The team must:

1. Discover the configurations that are actually available in AIONNICH.
2. Validate each configuration before execution.
3. Prefer existing documented configuration files and scripts.
4. Avoid inventing unsupported configuration values.
5. Run one simulation at a time.
6. Debug locally resolvable failures until the simulation completes successfully.
7. Compare against historical results when valid historical data exists.
8. Create a new baseline when no comparable historical result exists.
9. Present each completed simulation for user review before running the next simulation.
10. Do not modify source code silently during simulation validation.

---

# Configuration Discovery

Before running simulations, inventory all available configurations in:

```text
workspace/aionnich
```

Search for:

* Model configurations.
* Workload configurations.
* Topology configurations.
* Spectrum-X configurations.
* POD512 configurations.
* GPU-count configurations.
* DP, TP, and PP settings.
* ns-3 configurations.
* Analytical-backend configurations.
* Routing configurations.
* Congestion-control configurations.
* Example commands.
* Regression scripts.
* Historical experiment scripts.
* README commands.
* CI commands.

Search relevant directories such as:

```text
configs/
config/
examples/
scripts/
workloads/
models/
topologies/
network/
ns3/
analytical/
experiments/
benchmarks/
tests/
results/
outputs/
logs/
```

Use the actual repository structure if these directories have different names.

Create:

```text
reports/tasks/task-002/configuration-inventory.md
reports/tasks/task-002/configuration-inventory.csv
```

For every discovered runnable configuration, record:

| Field              | Description                              |
| ------------------ | ---------------------------------------- |
| Configuration ID   | Unique identifier                        |
| Source path        | Configuration or script path             |
| Backend            | ns-3, analytical, or other               |
| Network            | Spectrum-X, POD512, or other             |
| Model              | Model name                               |
| Workload type      | Training, inference, synthetic, or other |
| GPU count          | Requested GPU count                      |
| DP                 | Data parallelism                         |
| TP                 | Tensor parallelism                       |
| PP                 | Pipeline parallelism                     |
| Duration           | Simulated duration or iteration count    |
| Routing            | Routing algorithm                        |
| Congestion control | Congestion-control method                |
| Expected command   | Execution command                        |
| Historical result  | Matching result path, if found           |
| Validation status  | Valid, invalid, incomplete, or unknown   |

---

# Preferred Test Scope

Attempt to find valid configurations matching the requested target:

```text
Model: GPT-22B
Networks: Spectrum-X and POD512
GPUs: 128
DP: 1
TP: 8, 16, and 32
PP: values supported by the repository and less than 4
Duration: two hours of simulated workload
```

These values are preferred targets, not permission to fabricate unsupported configurations.

For each requested value:

1. Check whether an exact existing configuration exists.
2. Check whether a supported configuration can be generated using existing documented tools.
3. Validate GPU and parallelism placement.
4. Validate the model profile.
5. Validate network/topology support.
6. Validate the duration interpretation.

If the exact target is unsupported, select the nearest valid existing configuration and clearly document every difference.

Do not silently replace:

* Model.
* GPU count.
* DP.
* TP.
* PP.
* Network.
* Duration.
* Backend.

---

# Available-Configuration Selection Rules

Select simulations in this priority order:

## Priority 1: Exact Requested Configuration

Use an existing or officially generated configuration that exactly matches:

* GPT-22B.
* Spectrum-X or POD512.
* 128 GPUs.
* DP = 1.
* Requested TP and valid PP.
* Two-hour simulated duration.

## Priority 2: Closest Supported Configuration

When no exact match exists, choose the closest valid configuration based on:

1. Same network.
2. Same model.
3. Same GPU count.
4. Same DP.
5. Closest TP.
6. Closest PP.
7. Same workload type.
8. Closest duration.

Document all differences.

## Priority 3: Repository Smoke or Regression Configuration

If neither an exact nor close requested configuration exists, run an existing documented simulation that validates the current AIONNICH execution flow.

The test must still exercise:

```text
CLI/configuration
→ workload generation
→ topology/network setup
→ simulation backend
→ result collection
```

---

# Simulation Matrix Construction

After discovery, create the actual executable matrix:

```text
reports/tasks/task-002/experiment-matrix.csv
```

Include only validated runnable configurations.

Required columns:

```text
Run ID
Configuration path
Backend
Network
Model
GPU count
DP
TP
PP
Duration
Historical result
Historical comparability
Execution status
Review status
```

Do not create matrix rows for unsupported combinations merely to match the original requested count.

Present the discovered matrix to the user before executing the first simulation.

---

# Historical Result Discovery

Search for historical results in:

```text
workspace/aionnich/
reports/
results/
result/
output/
outputs/
simulation-results/
logs/
experiments/
benchmarks/
archive/
```

Also inspect:

* Git history.
* CSV files.
* JSON files.
* Log files.
* Markdown reports.
* Configuration snapshots.
* Plots.
* Archived experiment folders.
* Regression scripts.
* CI artifacts referenced by documentation.

For each historical result, record:

* Result path.
* Date.
* Associated commit, when known.
* Configuration path.
* Backend.
* Network.
* Model.
* Workload type.
* GPU count.
* DP.
* TP.
* PP.
* Duration.
* Batch size.
* Sequence length.
* Routing.
* Congestion control.
* Link parameters.
* Seed.
* ns-3 version.
* Result metrics.

Classify historical comparability as:

* Exact match.
* Comparable with documented differences.
* Not comparable.
* Unknown provenance.
* No historical result.

---

# Historical Comparison Is Conditional

## When an Exact or Comparable Result Exists

Compare the new result with the historical result.

For each metric calculate:

```text
absolute difference = new result - historical result
```

```text
percentage difference =
(new result - historical result) / historical result × 100%
```

Classify each metric as:

* Exact match.
* Within expected tolerance.
* Materially different.
* Inconclusive.
* Not comparable.

If a material unexplained difference exists:

1. Do not run the next simulation.
2. Investigate configuration, source, build, dependency, determinism, workload, network, and parser differences.
3. Repeat the current simulation when needed.
4. Debug locally resolvable problems.
5. Present the analysis for review.

## When No Comparable Historical Result Exists

Do not block or cancel the simulation.

Instead:

1. Run the validated configuration.
2. Verify successful completion.
3. Validate output integrity.
4. Extract all available metrics.
5. Record the result as a new baseline.
6. Store the effective configuration and environment.
7. Mark historical comparison as:

```text
No comparable historical result
```

8. State that regression comparison will become possible in future runs.

The absence of historical data is not a test failure.

---

# Per-Simulation Workflow

For each simulation:

## Step 1: Pre-Run Validation

Verify:

* Configuration exists.
* Referenced files exist.
* Backend is built.
* Model is supported.
* GPU mapping is valid.
* DP/TP/PP values are accepted.
* Network/topology is valid.
* Duration is understood.
* Output directory is clean or unique.
* Historical result status is known.

## Step 2: Present Pre-Run Information

Present:

* Run ID.
* Configuration source.
* Exact command.
* Effective parameters.
* Historical result path, if any.
* Historical comparability.
* Expected output.
* Required metrics.

Wait for user approval before running the simulation.

## Step 3: Execute

Run only the approved simulation.

Capture:

* Command.
* Environment.
* Start time.
* End time.
* Wall-clock runtime.
* Exit code.
* Standard output.
* Standard error.
* Peak memory when available.
* Generated files.

## Step 4: Debug Failures

If the simulation fails:

1. Reproduce the failure.
2. Identify the first substantive error.
3. Determine whether the issue is:

   * Build.
   * Configuration.
   * Missing file.
   * Workload.
   * Topology.
   * Backend.
   * Routing.
   * Congestion control.
   * Resource.
   * Result parsing.
4. Fix locally resolvable problems inside the approved task scope.
5. Rebuild if necessary.
6. Rerun the same simulation.
7. Continue until it succeeds or a verified external blocker is proven.

Do not move to another simulation while the current one has an unexplained failure.

## Step 5: Validate Results

Check:

* Exit code is 0.
* Expected output files exist.
* Output files are nonempty.
* Metrics are parseable.
* Simulation duration or iteration count is correct.
* No stale output was reused.
* No fatal warnings are hidden.
* Results are internally consistent.

## Step 6: Compare or Establish Baseline

When historical results exist:

* Compare and analyze.

When they do not exist:

* Create a new baseline.

## Step 7: Review Gate

Present the completed result.

Do not run the next simulation until the user explicitly approves proceeding.

---

# Required Metrics

Collect all metrics exposed by the selected configuration and backend.

Attempt to include:

## Workload and Model Metrics

* Simulated execution time.
* Iteration time.
* Completed iterations.
* Throughput.
* Compute time.
* Communication time.
* Communication-to-compute ratio.
* Collective duration.
* Pipeline bubble time.
* GPU idle time.

## Network Metrics

* Throughput.
* Goodput.
* Average latency.
* P95 latency.
* P99 latency.
* Flow completion time.
* Link utilization.
* Queue occupancy.
* Packet drops.
* ECN marks.
* PFC events.
* Retransmissions.
* Congestion events.
* Path distribution.
* Fairness.

## Simulation Metrics

* Wall-clock runtime.
* Peak memory.
* Events processed.
* Output size.
* Warning count.
* Error count.

If a metric is unavailable, document the missing instrumentation. Do not fabricate values.

---

# New Baseline Requirements

When no historical result exists, save:

```text
reports/tasks/task-002/baselines/<RUN-ID>/
```

Required files:

```text
command.txt
effective-config.json
source-config/
environment.md
commit.txt
stdout.log
stderr.log
exit-code.txt
runtime.txt
metrics.json
metrics.csv
validation.md
baseline-summary.md
checksums.txt
```

The baseline summary must state:

* This is a newly established baseline.
* No comparable historical result was found.
* Exact commit and branch.
* Exact configuration.
* Backend and dependency versions.
* Seed or determinism settings.
* Reproduction command.
* Known limitations.

---

# Per-Run Report

Create:

```text
reports/tasks/task-002/runs/<RUN-ID>/review-summary.md
```

Use:

## Simulation Test Review

**Run ID:**
**Configuration:**
**Backend:**
**Network:**
**Model:**
**GPUs:**
**DP:**
**TP:**
**PP:**
**Duration:**
**AIONNICH commit:**
**Historical result:**
**Historical comparability:**

### Execution Status

* Build status.
* Simulation status.
* Exit code.
* Output completeness.
* Warning count.
* Error count.

### Main Results

| Metric | Historical | New | Difference | Assessment |
| ------ | ---------: | --: | ---------: | ---------- |

When no historical result exists, use:

| Metric | New baseline |
| ------ | -----------: |

### Conclusion

Choose one:

* Matches historical result.
* Matches within accepted tolerance.
* Does not match historical result.
* Historical comparison is inconclusive.
* No comparable historical result; new baseline created.
* Simulation failed due to verified external blocker.

### Discrepancy Analysis

Include only when applicable.

### Recommended Decision

Choose one:

* Approve and proceed to the next simulation.
* Approve new baseline and proceed.
* Repeat the current simulation.
* Investigate further.
* Open a corrective task.
* Reject the result.

End with:

```text
This simulation is complete and awaiting your review. I will not run the next simulation until you explicitly approve proceeding.
```

---

# Task 002 Acceptance Criteria

Task 002 is complete when:

1. Available configurations are inventoried.
2. The actual executable matrix is documented.
3. Every approved matrix simulation completes successfully, unless a verified external blocker is accepted.
4. Every output is validated.
5. Historical comparisons are completed where comparable historical results exist.
6. Material mismatches are analyzed and resolved or explicitly accepted.
7. New baselines are created where no historical result exists.
8. No simulation is skipped solely because historical data is absent.
9. All commands, configurations, results, and environments are reproducible.
10. AIONNICH source changes, if required, are recorded and tested.
11. ASTRA-sim remains unchanged.
12. No commits or pushes are made without approval.

---

# Immediate Task 002 Instruction

Begin by:

1. Inventorying all runnable AIONNICH configurations.
2. Finding the closest supported configurations to the requested GPT-22B, Spectrum-X, POD512, 128-GPU matrix.
3. Finding matching historical results where they exist.
4. Creating the actual executable simulation matrix.
5. Presenting the first proposed simulation and exact command for approval.

Do not require historical results in order to run a valid simulation.

When no matching historical result exists, plan to run the simulation and create a new baseline.

Do not run the first simulation until the user approves its exact configuration and command.
