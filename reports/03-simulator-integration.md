# ns-3 and Network Backend Integration: AIONNICH vs. ASTRA-sim Upstream

## Scope and evidence

This report compares the checked-out `aionnich` repository at `f4cbaddb4ebd2e8ae4c3f69da624694dc68d74bc` with `astra-sim-upstream` at `518bd513ae110428cd62eb60efc0f3993fd53c70`. The comparison is about the ns-3/network-backend path, not the analytical simulator except where it clarifies AIONNICH's backend architecture.

Both ns-3 repositories are Git submodules and are **not initialized in this checkout**. Upstream pins `astra-network-ns3` at `f764bed...`; AIONNICH pins Alibaba's `ns-3-alibabacloud` at `7e3cb5b...`. Consequently, claims below about the parent-side adapter, build/invocation contract, generated inputs, and checked-in trace hooks are directly verifiable. Details implemented only inside either absent submodule cannot be compared here. No source repository was modified during this review.

## Executive summary

Upstream ASTRA-sim treats ns-3 as one interchangeable network backend. It builds the pinned backend in place, launches the backend's `AstraSimNetwork` scratch executable, and passes six largely orthogonal inputs: Chakra workload, ASTRA system JSON, ns-3 network config, remote-memory JSON, logical topology JSON, and optional communicator groups. The adapter turns every ASTRA `sim_send` into an ns-3 RDMA queue pair and uses callbacks to reconcile sends and receives.

AIONNICH is a substantially more opinionated full-stack integration. Its top-level build copies an Alibaba ns-3 fork into the ASTRA tree, compiles a debug/MTP binary, and exposes a stable `bin/SimAI_simulator` symlink. Its runtime CLI is reduced to a SimAI workload, a generated physical topology, an ns-3 transport configuration, and a thread count. Instead of relying primarily on ASTRA's native/custom collective configuration, it embeds MockNCCL/SimCCL-derived flow generation, NVLS/NVLSTree, NICH/NVSwitch nodes, GPU-aware physical topology, and a physical RoCE backend alongside ns-3 and analytical modes.

The largest operational weakness in both checked-in integrations is orchestration: neither supplies a production batch runner, wall-clock watchdog, retry policy, manifest, per-run seed contract, or atomic result directory. AIONNICH has stronger deterministic topology generation (seeded link jitter), more output streams, and documented sweep plans, but the plans are not equivalent to an implemented batch facility.

## Side-by-side comparison

| Concern | `astra-sim-upstream` | `aionnich` | Practical consequence |
|---|---|---|---|
| ns-3 dependency | Submodule `extern/network_backend/ns-3`, upstream `astra-network-ns3` | Submodule `ns-3-alibabacloud`, copied into `extern/network_backend/ns3-interface` | AIONNICH carries a vendor backend contract and stages it into SimAI; upstream builds its dependency in place. |
| Build | `./ns3 configure --enable-mpi`; `./ns3 build AstraSimNetwork -j $(nproc)` | CMake-builds ASTRA library, copies adapter/source tree into ns-3, then `./ns3 configure -d debug --enable-mtp` and `./ns3 build` | Upstream emphasizes MPI-capable current ns-3; AIONNICH emphasizes debug plus multithreaded parallel simulation (MTP). |
| Runtime binary | Direct versioned binary such as `ns3.42-AstraSimNetwork-default` under `extern/.../build/scratch` | Stable `bin/SimAI_simulator` symlink to `ns3.36.1-AstraSimNetwork-debug` | AIONNICH gives users a simpler entry point but hard-codes a backend version/profile path. |
| Runtime inputs | Chakra ET prefix, system JSON, physical network config, remote-memory JSON, logical topology JSON, communicator config | AICB/SimAI text workload, generated physical topology, SimAI ns-3 config, thread count; behavior also selected by `AS_*` environment variables | AIONNICH collapses more policy into its system layer and topology format. |
| Physical topology | Supplied through the backend config (`TOPOLOGY_FILE`); no generator in the parent repository | Checked-in Python generator and many generated topology artifacts | AIONNICH supports architecture exploration without hand-authoring backend files. |
| Logical topology | Explicit JSON `logical-dims`, independent of physical topology | Parallel groups and topology are inferred/constructed from workload, GPU/server layout, MockNCCL channels, and physical topology | Upstream cleanly separates logical and physical networks; AIONNICH more tightly couples workload parallelism, NCCL, and hardware. |
| Traffic | ASTRA workload events and native/custom collective algorithms call `sim_send`/`sim_recv`; adapter creates RDMA QPs | AICB workload layers are decomposed by embedded MockNCCL/SimCCL-style ring/tree/NVLS flow models, then injected into ns-3 | AIONNICH models NCCL implementation choices and flow dependencies more directly. |
| Links/queues | Backend config plus adapter options; ASTRA has `num-queues-per-dim`, communication/injection scaling, rendezvous | Per-link bandwidth/delay/error in topology; extensive HPCC/PFC/DCQCN-like config; GPU/NVSwitch node types; fixed PG/QP plumbing and monitoring | AIONNICH exposes much more transport and fabric detail in the parent checkout. |
| Completion | Tracks finished ranks and calls `Simulator::Stop`, `Destroy`, then `exit(0)` | Workload/flow completion is coordinated through SimAI callbacks; ns-3 setup is separated as `main1`, with MTP-aware critical sections | Both are callback driven; upstream's all-rank termination is explicit in the visible main. |
| Errors | File-open and message-accounting errors terminate; ns-3 setup failure returns `-1`; shell scripts use `set -e` | Mix of return codes, assertions, MockNCCL error logs, and `exit(-1)`; build scripts generally do not use `set -e` | AIONNICH has more domain checks but weaker shell fail-fast behavior. |
| Timeouts | No wall-clock timeout; simulation ends when all ranks finish | Configurable **simulated-time** stop value, but no wall-clock watchdog or launch timeout | A deadlock or pathological run can occupy a host indefinitely in either project. |
| Results | Backend FCT/trace behavior is configured in the ns-3 submodule; parent adapter logs and stdout are primary visible outputs | FCT, send, PFC, packet trace, queue length, bandwidth, rate, CNP, dimension utilization, detailed and end-to-end CSVs | AIONNICH provides a much richer analysis surface, though output paths are globally configured and collision-prone. |
| Determinism | No parent-level seed option or seeded topology generator | NICH topology jitter uses `random.Random(jitter_seed)` with default seed 1; static workloads/topologies otherwise aid repeatability | AIONNICH can reproduce generated jitter, but neither project defines a complete end-to-end RNG/metadata contract. |
| Batch runs | Individual example scripts only | Individual CLI plus many pre-generated topologies/results and sweep design documents; no checked-in general runner | External orchestration is required for reliable sweeps in both. |

## 1. Building and invoking ns-3

### Upstream

The current build path is concise and backend-native. [`build/astra_ns3/build.sh`](../astra-sim-upstream/build/astra_ns3/build.sh) first runs `protoc` for Chakra's event schema, enters the ns-3 submodule, configures with MPI, and builds only `AstraSimNetwork` using all host cores. Debug mode reconfigures with `--build-profile debug` and emits a verbose build. Cleanup delegates to `./ns3 distclean`; “clean result” is a no-op.

The example launchers do not use `./ns3 run`. They enter the backend's `build/scratch` directory and invoke a version/profile-specific executable directly. For example, [`Ring_allgather_16npus.sh`](../astra-sim-upstream/examples/run_scripts/ns3/Ring_allgather_16npus.sh) launches `ns3.42-AstraSimNetwork-default` with workload, system, network, memory, logical-topology, and communicator arguments. The debug script substitutes the debug binary under `gdb`.

An older compatibility path, [`build_3.17.sh`](../astra-sim-upstream/build/astra_ns3/build_3.17.sh), copies the adapter into an older ns-3 scratch tree, builds with Waf/GCC 5, and can build-and-run. This shows the migration from a copied scratch integration to the current backend-owned target.

### AIONNICH

AIONNICH adds two staging layers:

1. [`scripts/build.sh`](../aionnich/scripts/build.sh) deletes and recreates `astra-sim-alibabacloud/extern/network_backend/ns3-interface`, copies the entire `ns-3-alibabacloud` submodule into it, calls the nested build twice (clean-result then compile), and creates `bin/SimAI_simulator`.
2. [`build/astra_ns3/build.sh`](../aionnich/astra-sim-alibabacloud/build/astra_ns3/build.sh) CMake-builds the ASTRA/SimAI library, copies the ns-3 adapter headers/source and the ASTRA tree into ns-3's application tree, configures `-d debug --enable-mtp`, and builds ns-3.

The public invocation is therefore stable and compact:

```bash
AS_SEND_LAT=3 AS_NVLS_ENABLE=1 \
  ./bin/SimAI_simulator \
  -t 16 \
  -w ./example/microAllReduce.txt \
  -n ./Spectrum-X_128g_8gps_100Gbps_A100 \
  -c ./astra-sim-alibabacloud/inputs/config/SimAI.conf
```

This is easier to consume, but its symlink target hard-codes ns-3 `3.36.1` and the debug profile. The scripts also contain several robustness issues: the nested build has `# set -e` commented out, the outer ASTRA script executes a stray `cd` through an unset `BUILD_DIR`, and compiler assignments (`CC=... CXX=...`) are not attached to the following command. More seriously, the nested script attempts to copy `network_frontend/ns3/AstraSimNetwork.cc`, but that file is not tracked at the inspected revision (only `.h` files are present). A clean build therefore depends on an unrecorded/generated file or fails at that copy; the absence of `set -e` can obscure the original failure. Together these issues reduce reproducibility, portability, and error transparency.

## 2. Topology generation and representation

### Upstream

Upstream separates two concepts:

- Physical topology is selected indirectly through the ns-3 network configuration, whose `TOPOLOGY_FILE` points into the backend submodule.
- Logical topology is a small JSON file such as `{"logical-dims":["8","2"]}`. The product of dimensions determines the active NPU count and the dimension vector drives ASTRA queue allocation.

The parent repository provides sample logical JSON files but no physical-topology generator. Its ns-3 README also warns that system dimensions must match logical dimensions and that no checker enforces this.

### AIONNICH

[`gen_Topo_Template.py`](../aionnich/astra-sim-alibabacloud/inputs/topo/gen_Topo_Template.py) generates complete physical topology files. A header declares total nodes, GPUs per server/group, NVSwitch/NICH count, external switch count, link count, and GPU type; subsequent records identify switch nodes and give each link's endpoints, bandwidth, latency, and error rate.

The generator supports:

- Spectrum-X / rail-optimized single-ToR;
- Alibaba HPN single- or dual-plane and dual-ToR forms;
- DCN+ non-rail single- or dual-ToR forms;
- `MultiPodFatTree` with ring, mesh, or bipartite inter-ToR fabrics;
- `NichTopo_0`, a four-GPU-per-SICH/NICH hierarchy;
- `NichTopo_Wide`, configurable 16- or 32-GPU SICH groups with a fixed pod uplink budget.

It validates several structural constraints, derives switch/link counts, emits warnings for partial deployments, and supports independent ASW/PSW latency jitter. Jitter is reproducible because a local RNG is constructed with `--jitter_seed` (default 1). The repository also contains many ready-made topologies from 64 to 9216 GPUs, including multi-pod and NICH variants.

One caution: comments and implementation in `NichTopo_0` disagree about SICH-to-ASW rate. The design comment says a 4×4800G aggregate is divided over 16 links (1200G each), while the implementation deliberately assigns the full configured `nvlink_bw` to every link. Users should treat generated capacity, not the stale comment, as authoritative and validate aggregate bandwidth before experiments.

## 3. Links, queues, and transport configuration

### Upstream

The visible upstream adapter exposes ASTRA-level controls:

- `--num-queues-per-dim` (default one), expanded over every logical dimension;
- `--comm-scale` and `--injection-scale`;
- optional rendezvous protocol;
- per-message tags and per-source/destination source-port allocation.

Each `sim_send` creates an `RdmaClientHelper` on priority group 3, computes a window from either global or pair-specific BDP/RTT, installs the application on the source node, and starts it at simulation time zero. Send and receive bookkeeping tolerates the backend completing data before ASTRA posts its receive and handles messages split across multiple callbacks.

The detailed link, buffer, PFC, congestion-control, routing, and trace configuration resides in the absent `astra-network-ns3` submodule, so it is not safe to infer its exact current keys from this checkout.

### AIONNICH

AIONNICH checks much of that transport surface into its adapter's [`common.h`](../aionnich/astra-sim-alibabacloud/astra-sim/network_frontend/ns3/common.h) and sample [`SimAI.conf`](../aionnich/astra-sim-alibabacloud/inputs/config/SimAI.conf). Configurable behavior includes:

- packet payload, L2 chunk and ACK intervals;
- QCN enablement, dynamic PFC thresholds, pause duration and total pause limits;
- congestion-control mode, target utilization, EWMA, additive/hyper-additive increase, decrease interval, minimum rate, fast recovery/react, variable window, rate bound, multi-rate feedback, and PINT sampling;
- per-speed KMAX/KMIN/PMAX maps;
- buffer size, ACK priority, per-link error rate, and scheduled link-down event;
- flow, trace, FCT, PFC, queue-length, bandwidth, rate, and CNP files and monitor intervals.

At setup, node type 0 is a GPU/server endpoint, type 1 an external switch, and type 2 an NVSwitch/NICH. Per-link rate and delay feed route, RTT, BDP, switch headroom, and buffer calculations. RDMA hardware is attached to GPU and NVSwitch/NICH nodes, enabling the scale-up fabric to originate/terminate modeled transfers rather than existing only as a delay annotation.

The workload scheduler also retains queue-per-dimension/queue-level machinery from ASTRA and passes virtual-network/queue IDs through collective requests. MTP-aware critical sections protect shared flow maps in the ns-3 callback bridge.

## 4. Traffic generation

### Upstream

Upstream consumes Chakra execution traces (one per rank) and a system configuration selecting native or custom collectives. ASTRA's system/workload layer issues `sim_send` and `sim_recv`; the ns-3 adapter converts sends into RDMA QPs and calls ASTRA callbacks when ns-3 reports completion. The example suite includes generated microbenchmarks such as all-gather and all-reduce. Thus, traffic is event/collective driven rather than read from a static ns-3 flow file.

### AIONNICH

AIONNICH consumes AICB's human-readable layer workload. A row combines compute time with forward/weight-gradient/input-gradient collective type, size, and group information. The system layer supports transformer, data/model/hybrid parallel, microbenchmark, customized, and distributed-inference iteration modes.

Its principal enhancement is an embedded NCCL-like flow-model layer:

- `MockNcclGroup` builds ring, tree, NVLS, and NVLSTree channels and turns collectives into dependent point-to-point `SingleFlow` objects;
- `NcclTreeFlowModel` and related algorithms track channel, chunk, parent, child, and zero/non-zero-latency flow dependencies;
- environment switches select PXN, NVLS, NVLSTree, log level, and packet send latency;
- the ns-3 bridge correlates flow IDs/tags, can aggregate chunk completions, and handles NVSwitch/NICH endpoints;
- the same logical flow model can feed the ns-3 simulator or the physical RoCEv2/libverbs backend.

This makes AIONNICH's “traffic generator” more than a workload converter: it models collective implementation and fabric placement jointly. `SimCCL` and AICB remain separate submodules at the product boundary, while much MockNCCL behavior is embedded in `astra-sim-alibabacloud`.

## 5. Launch and simulation lifecycle

Upstream's visible `main` parses arguments, loads logical dimensions, creates one network and one `Sys` instance per NPU, sets up ns-3, fires every rank's first workload event, and calls `Simulator::Run()`. A global completion tracker stops and destroys ns-3 once every rank reports completion, then exits zero.

AIONNICH stages network setup in `main1(topology, config)`: read transport configuration, apply ns-3 defaults, and build the topology. The full main comes from the copied Alibaba ns-3 tree (absent here), which is why only the setup half is present in the parent adapter. The documented CLI and MTP structures show that the fork owns launch parsing and runs the SimAI workload with 1 or, recommended, 8–16 threads.

Neither integration provides run isolation. Both write or inherit paths relative to process state/configuration, and AIONNICH's default config uses shared absolute `/etc/astra-sim/simulation/*` files. Concurrent runs must receive unique configurations and result prefixes or they can truncate/overwrite one another's traces.

## 6. Errors and timeouts

### Upstream behavior

- Example scripts use `set -e` (and some `set -x`).
- Failure to open logical topology exits 1.
- ns-3 setup failure prints an error and returns `-1` from `main`.
- Missing tags, missing send events, and byte-count mismatches terminate immediately.
- There is no validation that physical/system/logical dimensions agree.
- There is no wall-clock timeout, deadlock detector, retry, crash artifact collector, or signal handling.

### AIONNICH behavior

- The topology generator raises `ValueError` for several invalid capacities/groupings and warns on partial topology generation.
- Runtime flow/channel errors are logged through `MockNcclLog`; critical tag/state failures use assertions or `exit(-1)`.
- The transport config includes `SIMULATOR_STOP_TIME`, but this is a simulated-time cutoff, not protection against a stalled process. Its sample value is extremely large.
- `ReadConf` does not check whether the config file opened successfully before parsing; topology/flow/trace `ifstream`s and many output `fopen`s are likewise not consistently checked.
- Build scripts generally lack fail-fast shell settings and expose no structured error summary.
- There is no wall-clock timeout, heartbeat, retry policy, or cleanup-on-signal runner in the checked-in executable workflow.

For both projects, external automation should use a wall-clock supervisor, capture stdout/stderr and exit status, kill the complete process group on timeout, preserve partial outputs, and classify timeout separately from simulator failure.

## 7. Traces and results

Upstream's parent adapter visibly records per-QP FCT fields (source/destination IP and ports, bytes, start, measured FCT, and standalone baseline FCT) through the backend callback. General logging is configurable through ASTRA's logger. Other network traces are backend-owned and cannot be enumerated without the submodule. Upstream examples do not create run directories, post-process outputs, or publish summaries.

AIONNICH exposes a broader result pipeline:

- ns-3/QBB packet trace for selected nodes;
- FCT and send-completion logs;
- PFC events;
- queue length, link bandwidth, source rate, and CNP monitors over configurable intervals;
- serialized simulation settings in trace output;
- detailed layer CSV, `EndToEnd.csv`, and dimension-utilization CSV;
- stdout summaries including completion tick and average latency per logical dimension.

The workload CSV writers are created only by rank 0 for separated logging. This avoids every rank emitting the same aggregate file, but names such as `EndToEnd.csv` still require one result directory per experiment. AIONNICH's config-specific monitor filename rewriting is fragile (`substr(idx+7)` assumes a particular config filename/path shape), and output `FILE*` creation is mostly unchecked.

## 8. Deterministic and batch execution

### Determinism

Both simulators are discrete-event systems driven by static inputs, so identical binaries and inputs should generally replay identically unless the backend or parallel scheduler uses uncontrolled randomness/tie-breaking. Neither parent repository records binary hashes, input hashes, ns-3 seed/run numbers, environment variables, host thread count, or full command line alongside results.

AIONNICH provides one explicit reproducibility mechanism: topology link-jitter generation uses a private seeded Python RNG, defaulting to seed 1. Its separate `retry_tail.py` also accepts a NumPy seed, but that is offline statistical analysis, not the ns-3 launch path. MTP may make ordering sensitivity more important; the checked-in code does not state or test deterministic equivalence across thread counts.

Upstream exposes no parent-level RNG seed in its ns-3 CLI. Any ns-3 RNG controls would have to be supplied through the missing backend or ns-3 global options.

### Batch support

Upstream supplies one-run examples and repository-wide tests, not a parameter-sweep facility. AIONNICH contains broad pre-generated topology/result artifacts, a matrix of missing experiments, and detailed sweep implementation plans. Those documents describe desirable hardening—detachment, `nohup`, `setsid`, traps, validation, and multiple run tags—but the referenced general sweep drivers are not present in this checkout. They should be treated as plans/evidence of manual campaign work, not implemented batch support.

For a reliable batch layer, either project still needs:

1. a declarative run manifest and Cartesian/filtered parameter expansion;
2. unique immutable run directories and generated per-run configs;
3. recorded Git/submodule revisions, hashes, environment, seeds, command, and start/end times;
4. wall-clock timeout and process-group cleanup;
5. explicit success criteria (exit zero plus expected final artifacts/markers);
6. bounded concurrency and resource accounting;
7. resume/skip/retry semantics that never confuse partial results with success;
8. deterministic regression tests across repeated runs and, for AIONNICH, MTP thread counts.

## AIONNICH-specific enhancements

### NICH / scale-up

- NICH/SICH is represented as ns-3 node type 2 (`NVSwitchNode`), with RDMA hardware and routing state, rather than as an analytical bandwidth shortcut.
- `NichTopo_0` models four GPUs per NICH, dedicated GPU–NICH NVLink, full-bipartite or non-rail NICH–ASW attachment, and optional PSW scale-out.
- `NichTopo_Wide` expands the NICH group to 16/32 GPUs and budgets 200 Tb/s of pod uplink while preserving distinct intra-group and inter-group latency.
- GPU type and GPUs per NICH/server are carried in the topology header and propagated into RDMA hardware.
- NVLS and NVLSTree flow generation explicitly use NVSwitch/NICH ranks and collective dependencies.

### Scale-out and topology

- Template generation covers rail/non-rail, single/dual ToR, single/dual plane, ring/mesh/bipartite inter-ToR, multi-pod fat tree, Alibaba HPN, DCN+, Spectrum-X, and NICH families.
- Link records independently specify bandwidth, latency, and error, with deterministic jitter for selected tiers.
- Routing can be recomputed after a configured link-down event, and QPs redistributed.
- The repository includes large ready-made topologies up to thousands of GPUs, far beyond upstream's parent-level logical examples.

### Backend and execution

- Alibaba's ns-3 fork adds MTP compilation and MTP-aware shared-map critical sections for multithreaded simulation.
- The same SimAI workload/flow layer supports analytical, ns-3 simulation, and physical RoCEv2 traffic generation backends.
- `FastBackEnd` provides latency prediction/caching hooks inside the system layer for accelerating repeated communication cases.
- Transport configuration exposes production-RDMA concerns (PFC, QCN/DCQCN-like controls, PINT, BDP windows, failure injection) directly in the SimAI repository.
- Result collection extends from FCT to congestion, queue, utilization, and layer/end-to-end application metrics.

### Workload and collective fidelity

- AICB-generated training/inference layers encode TP/DP/EP/PP behavior and overlap, not merely a communication microbenchmark.
- MockNCCL channel construction supports ring, tree, NVLS, and NVLSTree with chunk/channel dependency graphs and flow tags.
- PXN/NVLS/send-latency environment controls allow NCCL/fabric sensitivity experiments without rewriting the workload.
- Vidur integration extends the overall product to scheduled multi-request inference; this is above the ns-3 adapter, but it broadens the traffic arrival and execution model that can ultimately drive the backend.

## Conclusions

For a generic ASTRA-sim experiment, upstream is cleaner: its backend boundary, input separation, modern ns-3 build, and fail-fast example scripts are easier to reason about. It is the better reference for the canonical ASTRA Network API contract.

For architecture and networking research specific to AI clusters, AIONNICH is much richer. Its value is the vertically integrated path from AICB workload through NCCL-like flow decomposition into GPU/NICH/scale-out topology, detailed RDMA transport, and multi-layer traces. The cost is tighter coupling, hard-coded paths/version assumptions, more global mutable state, and inconsistent validation.

The highest-priority integration work for AIONNICH should be operational rather than another topology feature: make the build fail fast, validate every input/output open, replace global `/etc` outputs with per-run directories, add a wall-clock watchdog and structured exit reasons, record complete provenance/seeds, and turn the existing sweep plans into a tested resumable batch runner. Those changes would make its substantial NICH and backend enhancements trustworthy at scale.
