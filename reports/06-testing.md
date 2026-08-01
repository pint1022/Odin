# Test and Comparative Validation Report

Date: 2026-08-01 (UTC)  
Role: Test and Comparative Validation Engineer  
Scope: `aionnich` at `f4cbaddb4ebd2e8ae4c3f69da624694dc68d74bc` and `astra-sim-upstream` at `518bd513ae110428cd62eb60efc0f3993fd53c70`

## Executive summary

Neither checkout provides a runnable validation baseline in its current state.

- AIONNICH's documented analytical build configures and compiles the `AstraSim` static library, but final executable linkage fails because `Sys.hh` declares methods such as `Sys::boostedTick`, `Sys::register_event`, and `Sys::break_dimension` while no `Sys.cc` implementation exists in the checkout. The wrapper also emits six permission failures while trying to create hard-coded `/etc/astra-sim` directories. The ns-3 and supporting AICB/SimCCL submodules are uninitialized.
- Upstream cannot configure because all seven submodules are uninitialized; CMake first reports missing `extern/helper/fmt/CMakeLists.txt` and `extern/helper/spdlog/CMakeLists.txt`. Its only regression entry is `rt_template`, not a substantive named regression, and it fails during workload generation because the uninitialized Chakra submodule makes Python import `chakra` unavailable.
- No CTest, GoogleTest, Catch2, doctest, pytest, or unittest registrations were found in the checked-in simulator source. AIONNICH has no simulator test directory. Its numerous additions (Mock NCCL flow generation, NVLS/PXN, inferred bus bandwidth, overlap controls, physical RDMA, and extended workload behavior) therefore have no automated coverage in this checkout.

The repositories remained clean after evaluation. No system packages were installed and no source files were changed. Build output was generated only by the requested build attempt; diagnostic output is under `logs/testing/`.

## 1. Build requirements

### AIONNICH

Documented baseline (`README.md:136-156`, `docs/Tutorial.md:33-56`):

- Ubuntu 20.04, GCC/G++ 9.4.0, Python 3.8.10.
- Ninja must not be installed. The tutorial explicitly recommends removing both the system and pip Ninja packages; this is an unusual environmental constraint and was **not** performed.
- Clone with submodules (`git clone --recursive`), which should populate `aicb`, `SimCCL`, and `ns-3-alibabacloud` at the recorded gitlinks.
- Analytical: `./scripts/build.sh -c analytical`.
- ns-3 simulation: `./scripts/build.sh -c ns3`.
- Physical mode: libverbs/RDMA perf-test capability and MPI; the tutorial names OpenMPI/OpenMPI-devel and a working RDMA environment (`docs/Tutorial.md:334-355`).
- Full-stack workload generation can require an NVIDIA GPU/NGC environment and the AICB/AIOB Python dependencies. The Dockerfile uses `nvcr.io/nvidia/pytorch:25.05-py3`, installs `uv`, and consumes AICB and Vidur requirement files.
- The build wrapper expects permission to create `/etc/astra-sim/{inputs,simulation,config,topo,results}` (`astra-sim-alibabacloud/build.sh:39-44`).
- CMake requirement is 3.15 and the front-end asks for C++17, although the `AstraSim` library target is explicitly lowered to C++11 (`build/simai_analytical/CMakeLists.txt:2-7`; `astra-sim-alibabacloud/CMakeLists.txt:38`). GNU compiler minimum is 5.3.

Observed environment: CMake 4.4.2, GCC/G++ 13.3.0, Python 3.9.12, protoc 3.19.1, Make available. This is newer than the documented tested baseline. Every AIONNICH submodule was uninitialized (`git submodule status --recursive` prefixes each entry with `-`).

### ASTRA-sim upstream

Local build metadata establishes:

- CMake >=3.22 and C++17 (`CMakeLists.txt:9-13`); Release is the default.
- Initialized submodules for Chakra, fmt, spdlog, analytical network, csg-htsim, ns-3, and analytical remote memory.
- Protobuf development headers/library and compiler. CMake uses `find_package(Protobuf REQUIRED)` unless `PROTOBUF_FROM_SOURCE=True`.
- Network access at configure time for pinned yaml-cpp commit `a83cd31` through CMake `FetchContent`.
- The Dockerfile uses Ubuntu 22.04 and installs GCC/G++, Make, CMake, Boost program-options, OpenMPI, Python 3.11/venv, Graphviz, NumPy, SymPy, pandas, Python graphviz, Abseil 20240722.0, and protobuf 29.0 / Python protobuf 5.29.0.

The repository README delegates commands to the external project website rather than recording a self-contained local build recipe. The conventional local configure attempted here was `cmake -S astra-sim-upstream -B logs/testing/upstream-build`.

Observed environment has the basic compiler/CMake/protoc tools, but every upstream submodule was uninitialized.

## 2. Build attempts

| Repository / target | Command | Result | Evidence |
|---|---|---|---|
| AIONNICH analytical, documented wrapper | `./scripts/build.sh -c analytical` (120 s cap) | Configure succeeded; compilation reached 50% before the safety timeout. Six `/etc/astra-sim` permission errors were non-fatal because the scripts do not use `set -e`. | `logs/testing/aionnich-analytical-build.log` |
| AIONNICH analytical, resume configured build | `cmake --build .../build/simai_analytical/build --parallel 2` (180 s cap) | **Failed at final link.** `libAstraSim.a` built, then the executable had many undefined references to `AstraSim::Sys` methods. The checkout contains `Sys.hh` but no `Sys.cc` or other definitions. | `logs/testing/aionnich-analytical-resume.log`; `astra-sim/system/Sys.hh`; callers in `workload/Workload.cc` and `workload/Layer.cc` |
| Upstream configure | `cmake -S astra-sim-upstream -B logs/testing/upstream-build` | **Failed during configure.** `fmt` and `spdlog` submodule directories contain no `CMakeLists.txt`. | `logs/testing/upstream-cmake.log`; root `CMakeLists.txt:26-28` |
| AIONNICH ns-3 / physical | Not run | Dependencies unavailable/uninitialized; physical mode also requires real RDMA/MPI capability. Running either would not be a safe useful test in this environment. | `.gitmodules`; `scripts/build.sh:13-45`; tutorial requirements |

AIONNICH compiler diagnostics also found:

- `AstraParamParse.hh:55` and multiple `calbusbw.cc`/`Layer.cc` sites convert string literals to mutable `char*`.
- `MockNcclGroup.cc:675` (`genAllReduceFlowModels`) and `MockNcclGroup.cc:1852` (`gen_nvls_tree_inter_channels`) can reach the end of non-void functions. This is undefined behavior if those paths are reached.

## 3. Test inventory and execution

### AIONNICH inventory

- No simulator `tests/` or `test/` directory.
- No CMake `enable_testing()` or `add_test()` registrations.
- No recognized C++ or Python test framework markers in `astra-sim-alibabacloud`.
- `ncclFlowModel_test1_dimension_utilization_0.csv` is a result-like CSV, not an executable test or an asserted reference harness.
- README/tutorial example commands and many topology/configuration artifacts are manual demonstrations only: no expected output, tolerance, exit-code assertion, or runner is provided.
- AICB and SimCCL test content cannot be inventoried because those submodules are uninitialized. Vidur has no checked-in test directory in this checkout.

No AIONNICH runtime test could safely run because the analytical executable did not link and the ns-3/physical dependencies are unavailable.

### Upstream inventory

- `tests/run_all.sh` runs exactly one entry: `tests/rt_template/run.sh`.
- `rt_template` generates a Chakra trace, invokes the expected binary `build/astra_analytical/build/bin/AstraSim_Analytical_Congestion_Aware`, strips three bracketed log prefixes, and exact-diffs stdout against `refs/stdout.txt`.
- Its `readme.txt` still contains placeholders such as “Describe the binary under test”; it is a scaffold rather than a documented regression case.
- No CTest or unit-test framework registrations were found.

Execution of `bash astra-sim-upstream/tests/run_all.sh` **failed** before simulator invocation: `gen_chakra_traces.py:3` raised `ModuleNotFoundError: No module named 'chakra'`, consistent with the uninitialized Chakra submodule. See `logs/testing/upstream-tests.log`.

## 4. Common comparable scenarios

The input schemas and front ends have diverged, so comparison should use semantically equivalent scenarios rather than identical command lines/files. The strongest common core is the native collective engine: both trees implement Ring, AllToAll, HalvingDoubling, and DoubleBinaryTree algorithms plus logical ring/tree/torus topologies.

Comparable scenario families:

1. Single collective: AllReduce over ring, across 2/4/8 ranks, fixed latency/bandwidth, with 1 KiB through 1 GiB payloads.
2. Single collective: AllReduce over double-binary-tree with even and odd rank counts.
3. AllGather and ReduceScatter represented directly or through equivalent phases, checking completion time and bytes sent.
4. AllToAll on 4/8 ranks, including non-divisible payload sizes.
5. Multi-dimensional topology: 2-D ring/torus with per-dimension bandwidth and identical collective ordering.
6. Compute/communication sequence: compute → collective → compute, checking event ordering and total makespan.
7. Congestion: two simultaneous collectives sharing a constrained link in analytical backends, if both front ends can express it.
8. Remote-memory-disabled baseline, because upstream's test CLI requires a remote-memory configuration while AIONNICH does not offer a directly equivalent model.

Cross-project oracles should be normalized tuples rather than raw stdout: completion timestamp per rank, total makespan, per-rank bytes/messages, collective phase count, and deadlock/timeout status. Exact equality is appropriate for integer event counts; time should use an explicit absolute/relative tolerance after units are normalized.

## 5. Proposed benchmark matrix

| ID | Workload / algorithm | Scale | Payload | Network/topology | Primary metrics | Purpose |
|---|---|---:|---:|---|---|---|
| B01 | AllReduce / Ring | 2, 4, 8 | 1 KiB, 1 MiB, 1 GiB | 1-D uniform | makespan, bytes/rank, phases | Common correctness and scaling baseline |
| B02 | AllReduce / DoubleBinaryTree | 4, 8, then odd 7 | same | uniform tree | makespan, parent/child flow count, completion parity | Tree correctness and edge handling |
| B03 | ReduceScatter + AllGather | 4, 8 | divisible and remainder sizes | ring | combined time vs AllReduce, bytes | Collective decomposition invariant |
| B04 | AllToAll | 4, 8 | 4 KiB, 64 MiB, non-divisible | ring/direct where common | per-pair bytes, makespan | Routing/fan-out semantics |
| B05 | 2-D collective | 16, 64 | 1 MiB, 1 GiB | 4x4 / 8x8 rings | dimension utilization, phase order | Multi-dimensional parity |
| B06 | Compute → AllReduce → compute | 8 | 64 MiB | uniform | event order, exposed communication, total time | Workload scheduler parity |
| B07 | Two concurrent AllReduces | 8 | 64 MiB each | shared bottleneck | slowdown, fairness, completion order | Congestion behavior |
| B08 | Zero/tiny payload | 2, 8 | 0, 1, MTU-1, MTU, MTU+1 | ring/tree | termination, packet count | Boundary regressions |
| B09 | Determinism replay | 8 | 64 MiB | each common topology | hash of normalized outputs across 10 runs | Nondeterminism detection |
| B10 | Weak/strong scaling | 8–1024 where practical | fixed / proportional | analytical | runtime, peak RSS, simulated makespan | Simulator performance and model scaling |
| A01 | AIONNICH Mock NCCL Ring/Tree/NVLS | 8–128 | size sweep | single/multi-node | generated flow DAG invariants, time | Validate AIONNICH-only flow model |
| A02 | AIONNICH bus-bandwidth lookup/inference | TP/DP/PP/EP combinations | threshold sweep | analytical | selected algorithm/busbw, monotonic time | Validate `cal_busbw` and YAML lookup |
| A03 | AIONNICH overlap controls | 8–64 | fixed trace | overlap 0, .25, .5, 1 | exposed comm and makespan monotonicity | Validate overlap ratios |
| A04 | AIONNICH ns-3 NVLS/PXN | 16–128 | 1 MiB–1 GiB | supported topologies | path/flow counts, completion, no deadlock | Validate routing enhancements |
| A05 | AIONNICH analytical/ns-3/physical fidelity | feasible shared case | fixed | three backends | relative error and rank ordering | Cross-backend consistency |

Each benchmark should record commit/submodule hashes, compiler and dependency versions, seed, input digest, wall time, peak RSS, exit status, normalized result JSON, and raw logs. Establish golden results only after invariant tests pass and model assumptions are documented.

## 6. Untested AIONNICH enhancements and likely regressions

### Finding TV-001

- **Agent:** Test Engineer
- **Category:** Build completeness
- **Severity:** Critical
- **AIONNICH file and symbol:** `astra-sim-alibabacloud/astra-sim/system/Sys.hh`, class `AstraSim::Sys`
- **ASTRA-sim file and symbol:** `astra-sim/system/Sys.cc` and `Sys.hh` in upstream (implementation cannot currently build because submodules are absent)
- **Current behavior:** AIONNICH compiles its static library but cannot link `SimAI_analytical`.
- **Difference:** AIONNICH checkout has the declarations and many callers but no implementation translation unit.
- **Evidence:** Linker undefined references in `logs/testing/aionnich-analytical-resume.log`; `find` locates only `Sys.hh`.
- **Benefit or impact:** No analytical executable; all runtime and comparative testing is blocked.
- **Test status:** Reproduced.
- **Confidence:** High.
- **Recommendation:** Restore or generate the intended implementation, then add a clean-checkout CI build before functional benchmarks.

### Finding TV-002

- **Agent:** Test Engineer
- **Category:** Test coverage
- **Severity:** Critical
- **AIONNICH file and symbol:** Entire `astra-sim-alibabacloud`; especially `MockNcclGroup`, `NcclTreeFlowModel`, `cal_busbw`, and `Layer`
- **ASTRA-sim file and symbol:** `tests/run_all.sh` and `tests/rt_template` (minimal scaffold)
- **Current behavior:** No automated AIONNICH simulator tests exist; upstream exposes only one template regression.
- **Difference:** Major AIONNICH behaviors were added without an executable assertion suite, while the already-small upstream harness was not retained/adapted.
- **Evidence:** Filesystem inventory and absence of test framework/CMake registrations.
- **Benefit or impact:** Functional drift, hangs, timing errors, and invalid flow DAGs can ship undetected.
- **Test status:** Inventory complete for checked-in content; submodule tests unavailable.
- **Confidence:** High.
- **Recommendation:** Start with B01–B09 and A01–A04, registering fast invariants in CTest and retaining end-to-end goldens separately.

### Finding TV-003

- **Agent:** Test Engineer
- **Category:** NCCL flow generation
- **Severity:** High
- **AIONNICH file and symbol:** `MockNcclGroup.cc`, `genAllReduceFlowModels` and `gen_nvls_tree_inter_channels`; `MockNcclGroup.h` flow-generation APIs
- **ASTRA-sim file and symbol:** No Mock NCCL equivalent found; native collective implementations under `astra-sim/system/astraccl/native_collectives`
- **Current behavior:** Mock NCCL adds Ring/Tree/NVLS flow DAG generation for TP/DP/PP/EP group types and environment-controlled NVLS/PXN paths.
- **Difference:** AIONNICH-only enhancement with no unit tests; compiler proves two non-void paths lack returns.
- **Evidence:** `MockNcclGroup.h:141-172`, `MockNcclGroup.cc:675,1852`, and build warnings.
- **Benefit or impact:** Undefined behavior, corrupt flow models, or crashes on unsupported group/topology paths; high risk of algorithm-selection regressions.
- **Test status:** Compile diagnostic only; runtime blocked.
- **Confidence:** High.
- **Recommendation:** Add exhaustive group/scale/algorithm parameterized tests checking return validity, DAG acyclicity, byte conservation, peer bounds, and completion.

### Finding TV-004

- **Agent:** Test Engineer
- **Category:** Analytical performance model
- **Severity:** High
- **AIONNICH file and symbol:** `calbusbw.cc`, `calculateBusBw` / `cal_busbw`; `Layer.cc`, busbw selection; `AstraParamParse.hh`, overlap and busbw parameters
- **ASTRA-sim file and symbol:** No equivalent `cal_busbw` or overlap-ratio mechanism found
- **Current behavior:** AIONNICH selects/adjusts collective algorithms and bandwidth from GPU type, topology/scale, and TP/DP/PP/EP settings; it also applies user overlap ratios.
- **Difference:** AIONNICH-only fast analytical abstraction and workload controls.
- **Evidence:** `calbusbw.cc:167-228,296-335`; tutorial busbw schema and overlap flags at `docs/Tutorial.md:73-130`.
- **Benefit or impact:** Threshold discontinuities, wrong group lookup, invalid ratios, negative/excess overlap, or string mutability errors can silently bias predicted training time.
- **Test status:** Untested; compiler warns about mutable `char*` string literals.
- **Confidence:** High.
- **Recommendation:** Add table-driven boundary tests for every GPU/algorithm/group combination, property tests for finite positive bandwidth and monotonic message time, and validation tests for ratios outside `[0,1]`.

### Finding TV-005

- **Agent:** Test Engineer
- **Category:** Backend integration
- **Severity:** High
- **AIONNICH file and symbol:** `SimAiFlowModelRdma.cc`, `PhyMultiThread`, ns-3 `entry.h`, and build modes in `scripts/build.sh`
- **ASTRA-sim file and symbol:** network backends under `extern/network_backend/*` (uninitialized here)
- **Current behavior:** AIONNICH exposes analytical, ns-3, and beta physical RDMA modes, including NVLS metadata passed through flows.
- **Difference:** Physical RDMA and AIONNICH's specialized ns-3 integration are not covered by a checked-in automated test or cross-backend oracle.
- **Evidence:** build scripts/CMake conditional `PHY_RDMA` and `ANALYTI`; tutorial physical requirements; no test registrations.
- **Benefit or impact:** Divergent completion time/flow semantics, races in multithreaded physical mode, and ns-3 deadlocks may remain invisible.
- **Test status:** Not run: submodule/RDMA/MPI dependencies unavailable.
- **Confidence:** High for coverage gap; medium for specific runtime failures.
- **Recommendation:** Add a mock network API contract suite, small ns-3 smoke tests, race-sanitizer coverage where feasible, and A05 cross-backend tolerance checks.

### Finding TV-006

- **Agent:** Test Engineer
- **Category:** Build portability
- **Severity:** Medium
- **AIONNICH file and symbol:** `astra-sim-alibabacloud/build.sh`, `compile`; root/build CMake files
- **ASTRA-sim file and symbol:** root `CMakeLists.txt`; `Dockerfile`
- **Current behavior:** AIONNICH writes to `/etc/astra-sim` without checking failures, requires users to remove Ninja, and mixes C++17 front-end requirements with a C++11 library target. Upstream requires complete submodules plus configure-time yaml-cpp fetch.
- **Difference:** Both builds depend on undocumented or weakly enforced checkout/environment state; AIONNICH additionally assumes privileged filesystem access.
- **Evidence:** Six permission errors in build log; script lines 39-44; CMake target standard; upstream configure failure.
- **Benefit or impact:** Non-hermetic builds and confusing partial success; CI and unprivileged developers can receive late failures unrelated to their changes.
- **Test status:** Reproduced on an unprivileged environment.
- **Confidence:** High.
- **Recommendation:** Add prerequisite checks with immediate actionable failures, keep outputs under a configurable build/run directory, and test clean builds on the documented compiler plus a current compiler.

### Finding TV-007

- **Agent:** Test Engineer
- **Category:** Upstream regression harness
- **Severity:** Medium
- **AIONNICH file and symbol:** No corresponding harness
- **ASTRA-sim file and symbol:** `tests/run_all.sh`; `tests/rt_template/run.sh`; `gen_chakra_traces.py`
- **Current behavior:** The only upstream regression fails on missing Chakra and expects a binary path not produced by the root CMake file shown in this checkout.
- **Difference:** The test harness and current build layout appear stale or incomplete; AIONNICH contains no adaptation.
- **Evidence:** Runtime import failure; runner expects `build/astra_analytical/build/bin/AstraSim_Analytical_Congestion_Aware`, while root CMake builds a library and no such target is defined locally.
- **Benefit or impact:** A passing build would still not establish a runnable regression baseline.
- **Test status:** Reproduced through workload-generation stage.
- **Confidence:** High.
- **Recommendation:** Convert the template into named maintained cases, bind tests to actual CMake targets, declare Python dependencies, and run from a fresh recursive checkout in CI.

## 7. Validation gates before meaningful comparison

1. Populate submodules at the recorded gitlinks for both repositories (requires approval because it performs network writes into the checkouts).
2. Resolve AIONNICH's missing `Sys` implementation/build composition and achieve clean analytical linkage.
3. Establish one runnable upstream analytical binary and replace/repair the stale template test path.
4. Create a schema adapter producing semantically identical B01 inputs for both versions.
5. Validate invariants (termination, byte conservation, peer bounds, phase counts) before accepting timing deltas.
6. Expand through B02–B10, then test AIONNICH-only enhancements A01–A05 against explicit model-level oracles rather than upstream equivalence.

Until gates 1–3 pass, any performance or numerical comparison would conflate checkout/build failures with simulator behavior.
