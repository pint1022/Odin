# Model workload support: AIONNICH vs. upstream ASTRA-sim

## Scope and conclusion

This report compares the checked-out `aionnich` revision `f4cbaddb` with
`astra-sim-upstream` revision `518bd513`. “AIONNICH” below means the complete
checked-out stack: its modified ASTRA-sim (`astra-sim-alibabacloud`), its
vendored inference simulator (`vidur-alibabacloud`), and the AICB interface
described by the repository. The `aicb` and `SimCCL` submodules are not
initialized in this checkout, so AICB generator internals are not directly
auditable; claims about them are limited to the interface, example trace, and
call sites present here.

The systems make different trade-offs:

- **AIONNICH is model-aware and prescriptive.** Its native text trace encodes a
  transformer training schedule with TP/DP/PP/EP metadata, three fixed phases
  per row, AICB-derived byte counts and measured/profiled compute durations. It
  also adds a separate Vidur-based, request-level inference system with prefill,
  token-by-token decode, batching, scheduling, KV allocation and optional
  prefill/decode disaggregation.
- **Upstream is model-agnostic and trace-driven.** It consumes one Chakra ET per
  rank and executes its dependency DAG. Training, inference, prefill, decode,
  and all parallelism schemes are representable only insofar as the producer
  puts the appropriate compute, memory and communication nodes, dependencies,
  ranks and process groups into the traces. This is more general and preserves
  arbitrary overlap, but upstream does not itself derive a transformer trace
  from a model configuration.
- **The formats are not compatible.** AIONNICH removed the upstream Chakra
  feeder from its workload path and replaced it with a line-oriented parser and
  hard-coded state machines. Upstream cannot read AIONNICH text workloads;
  AIONNICH cannot read upstream `.et` files. A semantic converter, not a file
  rename, is required.

## Capability matrix

| Area | AIONNICH | `astra-sim-upstream` |
|---|---|---|
| Training | First-class transformer, DLRM, data/model/hybrid and microbenchmark policies; explicit forward, input-gradient and weight-gradient fields; gradient accumulation, virtual PP and activation-recompute scheduling | No named training policy or generator. Arbitrary training is supported through a supplied per-rank Chakra DAG |
| Inference | `DISTRIBUTED_INFERENCE` forward-only row replay in the simulator; substantially richer multi-request inference in Vidur | No inference scheduler or token semantics; a correctly generated Chakra inference DAG can be replayed |
| Prefill/decode | Vidur distinguishes prompt and token tasks, supports request traces/synthetic arrivals, batching and PD placement/transfer | Not intrinsic. Prefill and decode can be represented as ordinary named nodes/dependencies, but upstream does not interpret them |
| TP | Explicit header size and TP-labelled forward/input-gradient collectives; Vidur invokes one TP all-reduce predictor | Expressed by communicator membership or `involved_dim`; no TP semantics |
| DP | Explicit DP weight-gradient communication; DP inferred as `world/(TP*PP)` | Expressed by communicator membership; no DP semantics |
| PP | Header contains `pp`, `vpp`, `ga`, and one aggregate `pp_comm` byte count; Vidur models pipeline stages | Point-to-point send/receive nodes and dependencies can accurately represent pipeline transfers and schedules |
| EP | Explicit EP and DP/EP collective suffixes and All-to-All support; AICB/Vidur documentation still says inference EP/MoE integration is in progress | Expressed as arbitrary communicator groups and All-to-All nodes; no expert routing/load model |
| Collectives | AllReduce, AllGather, ReduceScatter, AllToAll, plus EP/DP_EP labels and a nominal composite type | AllReduce, AllGather, ReduceScatter, AllToAll; Broadcast falls back to trace runtime rather than network simulation; point-to-point send/receive supported |
| Chakra | No Chakra feeder in AIONNICH's workload implementation | Native Chakra ET v3 input, one `.rank.et` file per rank, with dependency, metadata, replay, compute, collective, P2P and memory nodes |
| Memory/storage | Training rows have no tensor identity, local memory nodes, storage or KV cache. Vidur tracks aggregate per-request KV occupancy and PD transfer | Chakra MEM_LOAD/MEM_STORE nodes issue remote-memory traffic; optional tensor read/write/lifetime tracking and local-memory/roofline modeling. No KV-specific policy or storage hierarchy semantics |
| Overlap | Fixed state-machine overlap plus user-supplied scalar TP/DP/EP/PP “overlap ratios” in analytical reporting | DAG dependencies expose concurrency; one CPU op, one GPU compute op and one non-receive GPU communication op may be in flight per simulated rank, allowing compute/communication overlap but serializing same-class work |

## AIONNICH training workload model

The workload header carries the scheduling policy and global parameters, for
example:

```text
HYBRID_TRANSFORMER_FWD_IN_BCKWD model_parallel_NPU_group: TP
  ep: EP pp: PP vpp: VPP ga: GA all_gpus: W
  checkpoints: ... checkpoint_initiates: ... pp_comm: Bpp
```

It is followed by a row count and rows of the form:

```text
name dependency
Fcomp Fcollective Fbytes
IGcomp IGcollective IGbytes
WGcomp WGcollective WGbytes update_time
```

All fields are whitespace-separated; the line breaks above are conceptual.
Compute/update times are simulator ticks and message sizes are bytes. The
`dependency` field is read and printed but not used to construct dependencies.
The selected policy instead runs a fixed forward/backward state machine over
the row order (`Workload.cc:1145-1535`). Consequently an AICB row sequence is a
schedule template, not a general execution graph.

For transformer traces, unqualified forward and input-gradient collectives are
classified as TP, while unqualified weight-gradient collectives are classified
as DP. `_EP` and `_DP_EP` suffixes override the group. The implementation uses:

\[
DP = \frac{W}{TP\,PP}, \qquad |G_{DP\_EP}| = \frac{DP}{EP}.
\]

It does not validate divisibility or `W == TP*PP*DP`; malformed combinations
can truncate integer divisions. EP is treated as a subdivision of DP rather
than an independent placement description. Group placement is inferred from
logical topology dimensions: TP occupies a prefix of dimensions determined by
`break_dimension(TP)`, and DP the remaining dimensions
(`Workload.cc:1083-1143`). This cannot express non-contiguous groups, arbitrary
rank layouts, different TP/EP placement per layer, or heterogeneous process
groups. Upstream communicator JSON/Chakra metadata can list the exact ranks,
although upstream currently collapses a subgroup's multi-dimensional native
collective to a one-dimensional ring (`CommunicatorGroup.cc:44-78`).

Pipeline behavior in AIONNICH is only partly a workload/network model. `pp`,
`vpp`, `ga`, checkpoint flags and policy state drive scheduling, but `pp_comm`
is a single aggregate byte count. It is not emitted as per-stage send/receive
traffic in `Layer`; the analytical report derives a PP exposure term from that
scalar. Upstream can instead encode each activation/gradient transfer as
matched send/receive nodes, with stage-specific sizes and dependencies.

## AIONNICH inference enhancements

The C++ `DISTRIBUTED_INFERENCE` mode is modest: it performs rows in forward
order and blocks on each row's forward collective (`Workload.cc:590-621`). It
has no requests, batching, prefill/decode distinction or KV state. Those
features reside in `vidur-alibabacloud`, outside the C++ workload engine.

Vidur adds the material inference enhancements:

- prompt tasks consume the prompt in one iteration and produce the first token;
  token tasks decode one token per iteration;
- request generation supports fixed/Poisson and trace-driven input, and the
  scheduler reports TTFT, token latency and end-to-end latency;
- distinct prefill and decode replicas can be selected, with a KV-transfer DAG
  edge or a calculated delay between them;
- per-replica memory capacity and per-request KV allocation affect admission;
- execution-time backends include profiled/regressed kernels, AICB data, and a
  SimAI TP communication query.

This is functionality upstream ASTRA-sim does not provide as a workload
frontend. However, it is a loose composition rather than one unified trace:
Vidur supplies scheduling and compute estimates, while it launches small
temporary SimAI workloads to estimate communication. In the SimAI predictor,
each query is just one forward `ALLREDUCE`; the byte formula is

\[
B_{TP} = H\,T\,2,
\]

where `H` is embedding width, `T` is the rounded number of batch tokens, and
the hard-coded `2` assumes a two-byte tensor. The returned communication time
adds empirical CPU overhead

\[
t = t_{SimAI} + t_{launch} + t_{skew}\,TP^{1.25}.
\]

This captures one common row-parallel TP synchronization, but not the number
and placement of collectives across attention/MLP/MoE layers, PP traffic, EP
dispatch/combine, fused collectives, or contention among concurrent replicas.
The README accurately labels SimAI inference backends as TP-only and EP/PP
adaptations as in progress.

## Communication mapping and formulas

### AIONNICH

AICB provides per-operation payload bytes. AIONNICH maps a row to a collective
group from both its phase and suffix, then maps the group onto selected logical
network dimensions. The detailed backend decomposes the collective through its
configured ring/tree/NCCL-like algorithms and topology; the analytical backend
computes a duration from an inferred bottleneck bus bandwidth and empirical
ratio tables.

For payload `B`, group size `p`, calibrated ratio `r`, and calculated bus
bandwidth `BWbus`, `Layer::compute_time` uses, for messages at least 1 MiB:

\[
t_{AR}=\frac{B}{r\,BW_{bus}}\frac{2(p-1)}p,
\qquad
t_{AG/RS/A2A}=\frac{B}{r\,BW_{bus}}\frac{(p-1)}p.
\]

The code's unit constants convert GB/s and seconds to ticks
(`Layer.cc:940-1034`). `compute_busbw` applies the inverse factors when
reporting algorithm and bus bandwidth (`Layer.cc:1037-1052`). For every
non-empty payload below 1 MiB, the model discards both bytes and collective
type and returns a rank-count lookup: 10, 12, 15, 66, 135, 200 or 320 us for
2, 4, 8, 16, 32, 64 or 128 ranks. Other rank counts in that range return zero.

The analytical overlap parameters post-process exposed time approximately as
`waiting *= (1 - overlap_ratio)` for DP, TP and EP (`Layer.cc:568-613`). This is
not temporal overlap or resource contention: it is a user-selected discount.
PP exposure uses `Bpp`, `VPP`, `GA` and the PP overlap ratio in a separate
formula (`Layer.cc:504-505`, duplicated at 734-735). Notably, the source default
for `pp_overlap_ratio` is 1, while the tutorial says all defaults are 0.

### Upstream

Upstream does not derive model message sizes. A Chakra collective node's
`comm_size` is passed unchanged to the selected collective implementation; a
send or receive node's size is passed unchanged to the network frontend
(`Workload.cc:304-446`). Thus the trace producer owns formulas such as
activation bytes, gradient shard bytes, routed-token volume and datatype.
Communicator membership can come from a JSON group file or PyTorch process-group
metadata in the trace.

Timing has two modes:

- replay uses `runtime_us * 1000` nanoseconds (and substitutes 1 ns for zero);
- roofline compute uses `OI = operations/tensor_bytes`, obtains performance
  from the configured roofline, and computes `t = operations/performance`.

Network timing comes from the configured collective and network frontend.
Dependencies decide when nodes become eligible; separate compute and
communication resources allow their overlap. This is semantically stronger
than an overlap percentage, but the hard-coded resource capacities prevent two
compute nodes or two non-receive communications from overlapping on one rank,
even if the captured system had multiple engines/streams
(`HardwareResource.cc:14-121`).

## Chakra, memory, KV cache and storage traffic

Upstream's Chakra path is its principal compatibility advantage. It accepts
dependency-rich compute, collective, send, receive, metadata, memory-load and
memory-store nodes. It can replay measured runtimes or roofline-model GPU
compute, send memory nodes through `AstraRemoteMemoryAPI`, and optionally derive
local tensor read/write timelines, lifetimes and capacity curves from Chakra
tensor metadata. Packet bundles also charge configured local-memory read/write
time. This is generic memory traffic—not an LLM KV-cache manager—and depends on
the trace containing correct tensor metadata.

AIONNICH's training rows contain no tensor IDs, tensor sizes for compute,
memory operations, parameter/optimizer fetches, checkpoint I/O, KV traffic or
storage operations. Compute durations may implicitly include GPU memory cost,
but that traffic cannot contend with communication or be remapped to a memory
system.

Vidur does explicitly reserve aggregate KV memory. Its checked-in formula is:

\[
B_{KV}=2\,T\,H_{MLP}\,L\,s,
\]

where `T` is token count, `H_MLP` is `mlp_hidden_dim`, `L` is number of layers,
and `s` is configured datatype bytes (`request.py:451-499`). PD transfer time is

\[
t_{PD}=B_{KV}/(BW_{configured}\,2^{30}/8).
\]

The simple link model likewise uses `flow_size / currently_free_bandwidth`,
gives a running flow all remaining bandwidth, and lacks propagation latency,
packetization, paths and realistic fair sharing. There is a TODO to replace it
with a higher-fidelity network (`interconnect.py:28-35,155-171`). KV is treated
as capacity and transfer volume, not as per-token HBM reads/writes or storage
traffic during attention.

## Compatibility issues

1. **Trace format and execution semantics are incompatible.** AIONNICH expects
   one shared text file and synthesizes rank behavior from topology dimensions;
   upstream expects per-rank Chakra files and executes explicit dependencies.
   A converter must materialize one DAG per rank, all process groups, P2P PP
   edges, compute units and memory nodes. Converting Chakra back to AIONNICH is
   generally lossy because the three-phase row cannot retain an arbitrary DAG.
2. **Collective naming is not portable.** AIONNICH's `_EP`/`_DP_EP` strings and
   phase-dependent meaning of bare names are private conventions. Chakra uses a
   collective enum plus explicit group metadata.
3. **Time units differ.** AIONNICH rows are used as ticks and often sourced from
   AIOB; upstream Chakra replay runtime is microseconds converted to
   nanoseconds. Any converter must establish the AICB tick frequency rather
   than copy values.
4. **Message-size meaning is producer-dependent.** Both pass a nominal byte
   count to collective code, but AIONNICH's analytical formulas assume that
   count is an algorithmic collective payload and then apply `(p-1)/p` bus
   factors. A Chakra generator that already records per-rank/on-wire bytes
   would be double-scaled if translated naively.
5. **Parallel rank layout is lost in AIONNICH.** Exact upstream process groups
   cannot always be represented by TP/EP sizes and dimension masks.
6. **Inference is not a drop-in ASTRA workload.** Vidur's request scheduler and
   KV state do not emit Chakra and the C++ `DISTRIBUTED_INFERENCE` policy does
   not reproduce Vidur behavior.

## Incorrect or risky assumptions in AIONNICH

The following are implementation findings, not merely unsupported features:

1. **KV width is wrong for standard attention.** KV cache scales with KV heads
   times head dimension (or attention hidden width), not the MLP intermediate
   width. `2*T*mlp_hidden_dim*L*s` can substantially overstate transfer and
   capacity, ignores TP/PP sharding and batch multiplicity, and is especially
   wrong for MQA/GQA models.
2. **The TP inference proxy under-models communication.** One `H*T*2`
   AllReduce is reused as “TP communication time”; datatype is hard-coded and
   topology/config are omitted from the in-memory cache key. Changing topology
   during one predictor lifetime can return stale latency. Hash comments also
   acknowledge that not all workload variables are included.
3. **Composite collectives are unreachable.** Parsing tests `ALLREDUCE` before
   `ALLREDUCEALLTOALL`; therefore a string such as
   `ALLREDUCEALLTOALL_EP` enters the AllReduce branch, fails the exact suffix
   cases, and receives group `NONE`. The later composite branch can never match
   (`Workload.cc:1325-1380`, repeated for all phases).
4. **Checkpoint-list parsing repeats one element.** The inner-loop index `j` is
   reset to 2 on every iteration and never persists, so a count greater than
   one repeatedly parses the first checkpoint/initiation layer
   (`Workload.cc:1189-1225`).
5. **The dependency column has no scheduling effect.** AICB traces may appear
   dependency-aware, but the parser discards the value. Correctness rests on
   row order and policy-specific code.
6. **PP traffic is not mapped to the network.** A single `pp_comm` is converted
   into reported exposure instead of stage-to-stage flows. It cannot capture
   direction, endpoints, bubbles, simultaneous microbatches or network
   contention, and the formula divides by `pp_overlap_ratio`; a documented
   value of zero risks division by zero in PP cases.
7. **Small-message timing is discontinuous and incomplete.** All payloads from
   2 bytes through 1 MiB have identical time for a given listed rank count;
   unsupported sizes such as 3, 5, 6, 7 or ranks above 128 yield zero. The
   boundary at 1 MiB abruptly switches model, and collective type/topology is
   ignored below it.
8. **Group construction assumes a regular factorization and placement.** There
   are warnings but no fatal validation for divisibility, EP nesting or header
   world size versus simulator size. Integer truncation and topology-dimension
   prefix mapping can silently simulate the wrong ranks.
9. **Overlap ratios are accounting knobs, not workload behavior.** Multiplying
   exposed time by `1-r` cannot model readiness, contention, stream priority,
   delayed gradients or a critical path; independently discounting groups can
   overcount simultaneous overlap. The documented and compiled PP defaults
   also disagree.
10. **PD network modeling is internally inconsistent.** One path inserts a
    `DummyLink` flow while another simply delays decode arrival using fixed
    configured bandwidth. Neither shares the detailed SimAI network used for
    TP collectives, so KV transfer cannot contend with TP/EP/PP traffic.
11. **Memory is capacity-only in inference.** KV allocation affects admission,
    but no HBM bandwidth is consumed for KV writes during prefill or reads and
    writes during decode. Model weights, activations and allocator/block
    fragmentation are not consistently part of the same capacity model.
12. **Feature claims need qualification.** The top-level repository advertises
    training and advanced inference, but the checked-in inference README says
    EP/MoE and SimAI PP/EP communication and GPU-memory adaptations are still in
    progress. Results should state the backend and model path used rather than
    claim uniform DP/TP/PP/EP support.

## Net assessment

AIONNICH's genuine enhancement is a convenient, model-aware workflow: AICB
turns transformer configurations/profiles into communication-bearing training
rows, while Vidur adds request-level LLM inference and PD separation. This is
useful for controlled sweeps and exposes TP/DP/EP labels directly in reports.
Upstream's advantage is fidelity to arbitrary captured/generated execution:
Chakra dependencies, explicit rank groups, P2P traffic, memory nodes and
roofline/replay modes form a more general workload contract.

For credible AIONNICH studies, treat AICB byte/timing generation as part of the
model under test, use the detailed network path for actual traffic, and avoid
interpreting analytical overlap or aggregate `pp_comm` as a schedule. The most
important remediation order is: correct KV sizing/sharding; emit unified
per-request TP/PP/EP/PD traffic; fix composite/checkpoint parsing; validate
parallel factorizations and units; replace scalar overlap and small-message
tables with dependency/resource-aware behavior; and add a Chakra import/export
path with explicit semantic and unit conversion.
