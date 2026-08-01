# Architecture and Upstream-Lineage Analysis

## Executive summary

`aionnich` is not a Git fork of the checked-out `astra-sim-upstream` repository. It is a separately initialized repository that imported and substantially adapted ASTRA-sim 1.0 source code under `astra-sim-alibabacloud/`. Its own README explicitly identifies the `ASTRA-sim-1.0` branch as the source. File identity and layout make upstream commit `cedcb3b81b0c908ab4fd33d7bf31c09f61186119` (2023-10-15, “Rename ns3-interface submodule dirname to ns3”) the strongest locally verifiable commit-level ancestor candidate. This is a commit on the untagged `ASTRA-sim-1.0_ns3` line, not an ASTRA-sim 2.x release.

The fork retains the 1.0 layer model—workload, `Sys`, collective algorithms/topologies, and a pluggable network API—but replaces the workload language and adds NCCL-like flow decomposition, detailed Alibaba NS-3 integration, an analytical bus-bandwidth model, and a physical RDMA mode. These are genuine architecture extensions. In contrast, moving APIs, statistics, or source implementation between files is refactoring.

Compatibility with current upstream is low. Current upstream uses Chakra execution traces, communicator groups, JSON/YAML configuration, remote-memory APIs, C++17, a reorganized `astraccl` layer, and modern analytical/HTSim/NS-3 frontends. `aionnich` uses a proprietary text workload, a large legacy `Sys` interface, legacy collective/topology classes, C++11, and its own backend contracts. There is no practical drop-in interchange of workloads, configuration, system code, or network backends.

Most importantly, the checked-out `aionnich` source has a build-blocking regression: `astra-sim/system/Sys.cc` is deleted at HEAD, but `Sys.hh` only declares core `Sys` methods. The CMake source glob cannot provide definitions for the constructor, destructor, event handler, or collective-generation path.

## Scope and method

The comparison is between the exact checked-out trees. Both repositories were inspected read-only; only this report was created. Evidence included refs and logs, tree/blob identities, source layout, build files, entrypoints, APIs, workload engines, and the change history of `astra-sim-alibabacloud/` since its import.

Generated build output under `astra-sim-upstream/build/` was excluded from architectural classification. Uninitialized `aionnich` submodules were treated as declared external components, not inspected source. No claim below depends on a network fetch.

## Repository identity and history

| Repository | HEAD | Commit date | Subject | Remote |
|---|---|---|---|---|
| `aionnich` | `f4cbaddb4ebd2e8ae4c3f69da624694dc68d74bc` | 2026-07-02 | `add the latest configurations run` | private GitLab `stevenw/aionnich.git` |
| `astra-sim-upstream` | `518bd513ae110428cd62eb60efc0f3993fd53c70` | 2026-03-26 | `update ns3 submodule (#366)` | `github.com/astra-sim/astra-sim.git` |

Both working trees were clean at inspection time. `aionnich` declares `SimCCL`, `aicb`, and `ns-3-alibabacloud` as submodules; all three are uninitialized in this checkout. Current upstream declares Chakra, analytical network and memory backends, NS-3, HTSim, `fmt`, and `spdlog` dependencies as submodules.

### Shared-ancestor determination

There is **no shared Git ancestor in the recorded repository histories**.

- `aionnich` begins with root commit `1854d8998b5fdfed0afb9daf46790792380a140b` on 2024-10-18, subject `Add origin source code`. It adds the ASTRA-derived sources as ordinary files.
- No ASTRA upstream commit is a parent of that root commit, and the imported directory is not a Git submodule.
- The two repositories use independent object databases. A direct `merge-base` cannot name the other repository's commit; more importantly, `aionnich`'s root has no parent through which an upstream commit could be ancestral.
- Shared file blobs prove source lineage, but blob identity is not commit ancestry.

Thus the precise result is: **shared source lineage, but no shared Git commit ancestry**.

## Most likely ASTRA-sim ancestor

### Conclusion

The release family is **ASTRA-sim 1.0**, after the NS-3 entrypoint was moved into the ASTRA tree. The best commit-level candidate available locally is:

`cedcb3b81b0c908ab4fd33d7bf31c09f61186119` — 2023-10-15 — `Rename ns3-interface submodule dirname to ns3`

This commit is the tip of the locally available `origin/ASTRA-sim-1.0_ns3` ref. There is no numbered 1.0 tag in the checkout, so it is more accurate to call this an untagged branch snapshot than “release 1.0.0.”

### Confidence and evidence

Confidence is **high for the 1.0 family** and **moderate for the exact commit**.

- `aionnich/README.md` says verbatim that `astra-sim-alibabacloud` is extended from the upstream `ASTRA-sim-1.0` branch.
- The imported tree contains the 1.0-era `Layer` workload model, `system/collective`, `system/topology`, `AstraMemoryAPI`, `FastBackEnd`, and legacy NS-3 entrypoint. These do not describe the 2.x Chakra architecture.
- The NS-3 directory name matches `cedcb3b8`'s stated rename.
- Comparing the 138 distinct blobs in the initially imported ASTRA subtree against that commit finds 43 identical blob IDs. Ignoring repeated empty-file blobs, at least 36 named implementation/header files are byte-identical, including `AstraMemoryAPI.hh`, `CallData.hh`, `CollectivePhase.*`, `DMA_Request.*`, `QueueLevels.*`, `Rendezvous*`, and numerous topology files.
- The earlier `f653a46699975feeeee5cac984e7ec9e90d7aff3` (“Move entrypoint from ns3 repo/scratch”) has the same 43-blob score because the shared core did not change across those commits. The later rename is preferred because the imported path is `network_frontend/ns3`.
- Much of the initial import was already Alibaba-specific, so exact whole-tree equality is neither present nor expected.

The nearest numbered upstream releases are 2.0.0 (`a1458c66`, 2023-09-28), 2.1.0 (`3defae42`, 2023-10-02), and 2.2.0 (`56b533f4`, 2023-11-09), but the fork is not based on those 2.x lines despite date proximity.

## Directory and module mapping

| `aionnich` | Current upstream counterpart | Classification / notes |
|---|---|---|
| `astra-sim-alibabacloud/astra-sim/system/` | `astra-sim/system/` plus `astra-sim/common/` | Same orchestration role; fork retains a much larger legacy surface and places APIs in `system` rather than `common`. |
| `system/collective/` | `system/astraccl/native_collectives/collective_algorithm/` | Renamed/reorganized upstream. Fork adds NCCL tree flow modeling. |
| `system/topology/` | `system/astraccl/native_collectives/logical_topology/` | Renamed/reorganized upstream. Most legacy topology concepts still correspond. |
| `system/fast-backend/` | No current in-tree equivalent | Legacy fast backend removed upstream. |
| `system/memory/SimpleMemory.*` | `extern/remote_memory_backend/analytical` via `AstraRemoteMemoryAPI` | Concept retained upstream behind a redesigned external API. |
| `system/scheduling/OfflineGreedy.*` | `system/scheduling/OfflineGreedy.*` | Direct conceptual mapping; implementations have diverged. |
| `astra-sim-alibabacloud/astra-sim/workload/` | `astra-sim/workload/` | Same layer position, incompatible engines: text `Layer` iteration versus Chakra DAG feeder. |
| `network_frontend/analytical/` | `network_frontend/analytical/{common,congestion_aware,congestion_unaware}` | Same backend class, completely different model/API organization. |
| `network_frontend/ns3/` + `ns-3-alibabacloud` | `network_frontend/ns3/` + `extern/network_backend/ns-3` | Forked detailed-network integration with NCCL/RDMA flow tags and Alibaba NS-3. |
| `network_frontend/phynet/` | No upstream counterpart | Genuine fork addition: MPI/bootstrap and physical RDMA traffic generation. |
| `AstraComputeAPI.hh`, `AstraNetworkAPI.hh`, `AstraSimDataAPI.hh` in `system/` | Same interfaces in `common/` | Upstream relocation/refactoring plus later interface evolution. |
| `AstraMemoryAPI.hh` | `common/AstraRemoteMemoryAPI.hh` | Renamed and redesigned upstream. |
| Root topology/config files and `inputs/topo`, `inputs/ratio` | `inputs/network/*.yml`, `inputs/system/*.json`, `examples/` | Different configuration ecosystems and topology semantics. |
| `aicb` | `extern/graph_frontend/chakra` and Chakra-format generators | Both supply workloads, but with incompatible schemas and ownership. |
| `SimCCL` | `system/astraccl` | Both describe/decompose collectives; SimCCL is an external Alibaba subsystem while AstraCCL is integrated upstream. |
| `vidur-alibabacloud` | No upstream counterpart | End-to-end inference request/scheduling simulator integrated at suite level. |
| No equivalent | `network_frontend/htsim/` | Upstream-only backend. |
| No equivalent | `tests/`, GitHub workflows, `utils/` | Upstream validation and developer infrastructure absent from the fork. |

## Added, removed, renamed, and modified modules

The terms below are relative to the shared ASTRA 1.0 lineage, while compatibility comments compare with current upstream.

### Genuine additions in `aionnich`

- **NCCL-like flow decomposition:** `MockNccl*`, `MockNcclChannel`, `MockNcclGroup`, `MockNcclQps`, `NcclTreeFlowModel`, and `SimAiFlowModelRdma` translate collectives into tagged point-to-point flows and channels.
- **Three fidelity modes:** analytical bus-bandwidth simulation, detailed NS-3 packet/RDMA simulation, and physical RDMA generation through `phynet`.
- **Physical topology augmentation:** GPU/NVSwitch mapping, Alibaba HPN/Spectrum-X/NichTopo definitions, dual-ToR/plane variants, and large topology/config catalogs.
- **Workload semantics beyond the inherited model:** data/model/tensor/pipeline/expert-parallel paths, transformer/DLRM scheduling, and distributed/multi-request inference hooks.
- **Bandwidth calculation:** `calbusbw.*`, ratio inputs, and topology-aware analytical parameters.
- **External full-stack composition:** AICB, SimCCL, Alibaba NS-3, and Vidur integration at repository level.
- **Multi-thread/physical support:** `BootStrapnet`, `PhyMultiThread`, MPI bootstrap, RDMA flow handling, and synchronization.

### Upstream-only additions since the fork line

- Chakra v3 execution-trace feeder and dependency-DAG execution.
- `CommunicatorGroup`, `CollectivePlan`, and per-workload-node collective implementation lookup.
- `astraccl` separation, custom collectives, and reorganized native algorithms/topologies.
- `AstraRemoteMemoryAPI`, analytical remote-memory backend, local-memory usage tracking, and hardware-resource modeling.
- Congestion-aware and congestion-unaware analytical frontends with shared event queues and parsers.
- HTSim frontend/backend support.
- Structured logging (`spdlog`), YAML network parsing, JSON system configuration, C++17, and centralized CMake dependency management.
- Tests, CI workflows, example traces/scripts, and developer utilities.

### Removed or absent from current `aionnich`

- Chakra and all current upstream trace/communicator-group machinery.
- Current `common/` layer and its logging implementation.
- Current remote-memory contract and backend.
- HTSim frontend.
- Current custom-collective and `CollectiveImplLookup` modules.
- Current tests/CI and most upstream examples.
- At `aionnich` HEAD specifically, `AstraSimNetwork.cc` and **`Sys.cc`** have been deleted since the initial import.

### Renames and relocations

- Legacy `system/collective` → upstream `system/astraccl/native_collectives/collective_algorithm`.
- Legacy `system/topology` → upstream `system/astraccl/native_collectives/logical_topology`.
- Legacy `AstraMemoryAPI` → upstream `AstraRemoteMemoryAPI`.
- API headers in legacy `system/` → upstream `common/`.
- Fork `RecvPacketEventHadndlerData.*` contains a persistent `Hadndler` typo; upstream has the corrected `RecvPacketEventHandlerData.*`.
- Fork workload CSV output remains in `workload/CSVWriter.*`; current upstream places `CSVWriter.*` in `system/`.

### Heavily modified inherited modules

`Sys`, `Workload`, `Layer`, `AstraNetworkAPI`, `Common`, `Ring`, `HalvingDoubling`, `GeneralComplexTopology`, `OfflineGreedy`, statistics/CSV output, NS-3 entry plumbing, and analytical entry plumbing have all diverged materially. Since the 2024 import, 29 ASTRA source paths were changed at `aionnich` HEAD: 26 modified, two deleted, and `calbusbw.{cc,h}` added.

## End-to-end execution architecture

### `aionnich`: SimAI analytical mode

1. `AnalyticalAstra.cc` parses a single SimAI command-line/config singleton, derives GPU and NVSwitch dimensions, and creates one `AnalyticalNetWork` and one `Sys` object.
2. `Sys` constructs the legacy workload/system state, collective implementations, streams, queues, topology, compute/memory behavior, and callbacks.
3. `Workload::fire()` parses/starts the AICB-style text workload. `Workload` iterates `Layer` objects according to the selected parallelism policy (microbenchmark, DP, MP, hybrid/transformer/DLRM, or inference).
4. Compute operations are scheduled through `AstraComputeAPI`; communication operations ask `Sys` to generate a `DataSet` and one or more `CollectivePhase`/`BaseStream` instances.
5. Ring, halving-doubling, all-to-all, double-binary-tree, or NCCL-tree logic decomposes a collective. In the SimAI extension, MockNCCL/flow-model code can generate channel- and flow-tagged transfers.
6. `front_end_sim_send`/`front_end_sim_recv` cross the `AstraNetworkAPI` boundary. `AnalyticalNetWork` schedules completions in `AnaSim` using estimated bus bandwidth rather than packet simulation.
7. Callback events return through `Sys::handleEvent`, advance stream/data-set state, notify `Workload::call`, release dependencies, and issue the next layer operation.
8. `AnaSim::Run()` drains the event loop; workload/CSV/network statistics are emitted and the simulator is stopped/destroyed.

### `aionnich`: detailed NS-3 mode

The workload-to-collective path is the same through `Sys`. The NS-3 `AstraSimNetwork`/`entry.h` adapter instead maps flow tags to source/destination addresses and queue pairs in `ns-3-alibabacloud`, simulates packets, congestion control, PFC/ECN and RDMA completion, matches send/receive wait maps, and calls the stored ASTRA handler. This is the highest-fidelity SimAI path.

### `aionnich`: physical mode

`SimAiMain.cc` bootstraps MPI ranks, initializes optional RDMA, registers network callbacks, builds one `Sys` per physical rank, and starts its workload. `SimAiPhyNetWork` turns simulated send/receive operations into `PhyNetSim`/RDMA flow operations. Completion callbacks feed the same `Sys`/workload state machine; ranks synchronize, destroy the physical loop, and finalize MPI.

### Current upstream ASTRA-sim

1. A frontend main parses separate workload, communicator-group, system, remote-memory, and network configurations.
2. The network parser constructs topology and a shared discrete-event queue. One network API and `Sys` are created per NPU; a remote-memory API is shared where applicable.
3. Each `Sys` parses JSON system policy and constructs `CollectiveImplLookup`, native/custom collective facilities, logical topologies, memory/compute models, and a `Workload`.
4. `Workload::fire()` uses Chakra `ETFeeder` to issue dependency-free DAG nodes. Compute, memory, collective, and native send/receive nodes are dispatched independently; communicator metadata selects the participating group.
5. For a collective, `Sys` selects a per-operation/per-node implementation, constructs phases/streams, and uses the common `AstraNetworkAPI`. For native send/receive it calls the frontend API directly.
6. The chosen congestion-aware/unaware analytical, NS-3, or HTSim backend schedules delivery/completion on its event engine.
7. `Sys::handleEvent` routes completion back to workload, memory, send, receive, or collective handlers. Chakra dependencies are released and newly ready nodes are issued.
8. The frontend drains the shared event queue, reports structured statistics/logs, deletes systems, and shuts down logging.

## Architecture enhancements versus refactoring

### Genuine SimAI enhancements

The following change behavior or introduce a new replaceable subsystem, and therefore are architectural:

- NCCL-faithful channel/tree/flow decomposition instead of only choosing a generic collective algorithm.
- A common system/workload core that can target analytical timing, detailed packet simulation, or physical RDMA traffic.
- AICB/SimCCL/Vidur composition and richer training/inference parallelism semantics.
- NVSwitch and Alibaba data-center topology awareness, including explicit flow tags and topology catalogs.
- Detailed telemetry and topology-dependent bus-bandwidth estimation.
- Multi-thread/rank coordination for large detailed simulations.

### Refactoring or packaging changes

These should not be credited as new capabilities by themselves:

- Renaming `collective`/`topology` directories into upstream `astraccl` namespaces.
- Moving common API headers out of `system`.
- Moving `CSVWriter` between workload and system directories.
- Splitting upstream analytical code into common and congestion-specific subdirectories.
- Moving NS-3 entrypoint code into the ASTRA repository or renaming its directory.
- Splitting constructor/config parsing and implementation lookup into smaller current-upstream classes.
- Build-script, CMake, formatting, logging-library, and configuration-file reorganizations unless they enable an independently meaningful capability.

## Regressions and compatibility risks

### Critical: missing `Sys.cc` in `aionnich`

`Sys.cc` existed in the root import and is deleted at HEAD. Searches of the current `astra-sim-alibabacloud` tree find no definitions for `Sys::Sys`, `Sys::~Sys`, `Sys::handleEvent`, or `Sys::generate_collective`; `Sys.hh` only declares them. The CMake library globs `system/*.cc`, so stale objects in checked-in build directories may mask the problem locally, but a clean source build should fail at link time. This also makes the end-to-end core unauditable at HEAD without consulting history. Restore or intentionally replace the implementation and add a clean-build CI check.

### High: upstream API and data-model incompatibility

- Constructor signatures and ownership differ radically; current upstream frontends cannot instantiate SimAI `Sys`, and SimAI frontends cannot instantiate current upstream `Sys`.
- Workloads are incompatible: SimAI text layers/AICB versus Chakra protobuf execution traces and communicator-group metadata.
- Configurations are incompatible: SimAI command flags, topology text, ratio CSV, and NS-3 `.conf` versus upstream YAML network and JSON system files.
- Network API structures, tags, rendezvous handling, and backend callback assumptions have diverged. Dropping in current upstream NS-3, analytical, or HTSim backends is unsafe.
- Memory APIs diverged from `AstraMemoryAPI`/`SimpleMemory` to remote-memory semantics.
- Collective selection diverged from legacy enums/vectors to `CollectiveImplLookup`, communicator groups, collective plans, and custom algorithms.

### High: maintainability and validation regressions

- `aionnich` has no equivalent to upstream unit/regression tests or CI workflows. The only test-like artifacts found are logs/output data, not an automated source test suite.
- Core logic is concentrated in very large `Workload.cc`, `Layer.cc`, `Sys.hh`, global maps, and backend entry headers. This increases coupling and makes mode-specific state hard to isolate.
- CMake uses broad globs, duplicates `system/*.cc`, pins C++11, and conditionally excludes sources by regex. This is fragile compared with explicit modern targets and hides accidental file removal until link time.
- Entry points allocate network and system objects without corresponding deletion on normal completion, while upstream explicitly destroys each `Sys` and owns network APIs with `unique_ptr`. This is mostly process-lifetime leakage but obstructs repeated in-process runs.
- Several required components are uninitialized submodules, and build scripts assume `/etc/astra-sim` plus backend-specific generated build directories. Reproducibility depends on external state.

### Medium: behavioral divergence and portability

- Analytical mode creates a single `Sys` that models all GPUs, whereas current upstream creates one `Sys`/network API per NPU. That is a deliberate speed optimization but changes concurrency, callback, and communicator semantics; upstream correctness fixes may not transfer directly.
- The physical path relies on MPI, global singleton/state, optional RDMA compile flags, and manually coordinated teardown. It is a useful capability with a larger deadlock/resource-lifetime surface.
- Explicit NVSwitch nodes are folded into physical dimensions and then partly excluded from GPU counts. Any inherited collective code that assumes all dimension members are compute NPUs is a correctness risk.
- SimAI's detailed mode is coupled to its Alibaba NS-3 fork and custom flow tags. Upstream NS-3 fixes—such as matching, rendezvous, or ownership changes—must be manually ported and revalidated.
- The misspelled `RecvPacketEventHadndlerData` path and other legacy naming prevent straightforward file-level merges.

### Licensing and contribution-boundary risk

The imported ASTRA source originates under MIT, while many SimAI files carry Apache-2.0 headers and the repository root has its own license. This report makes no legal conclusion, but provenance should remain file-explicit when upstream code is ported. A conventional fork/merge history or a machine-readable upstream-base record would substantially improve future attribution and rebasing.

## Recommended architectural actions

1. Restore the missing `Sys.cc` (or commit an intentional replacement) and prove a clean build for every mode in CI.
2. Record `cedcb3b8` as the provisional upstream base in a lineage manifest, including branch name, confidence, and known pre-import Alibaba modifications.
3. Add adapter boundaries for workload input, collective planning, and network backends. Keep SimAI semantics behind those adapters rather than continuing to expand `Sys` and global entry headers.
4. Build compatibility tests at the `AstraNetworkAPI` callback boundary and golden tests for collective flow decomposition before porting upstream fixes.
5. Decide explicitly whether current-upstream compatibility is a goal. If yes, migrate in stages: common APIs/ownership and C++17 first, Chakra/communicator adapters second, `astraccl` selection third, backend adapters last. A direct source merge is not viable.
6. Treat analytical single-`Sys`, explicit NVSwitch membership, and physical RDMA as SimAI-specific architecture and document their invariants; do not “normalize” them as refactors during an upstream sync.

## Bottom line

`aionnich` is best understood as a product-level SimAI platform containing a deeply modified ASTRA-sim 1.0 derivative, not as a downstream branch of modern ASTRA-sim. Its major value lies in NCCL-aware communication decomposition, Alibaba topology/network fidelity, multiple simulation fidelities, and full training/inference ecosystem integration. Its primary architectural liabilities are the absence of preserved Git lineage, extreme API/data-model drift, weak automated validation, tight global coupling, and the current missing core `Sys.cc` implementation. Any upstream reconciliation must be adapter-led and test-led rather than attempted as a directory merge.
