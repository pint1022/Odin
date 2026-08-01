# Network-management algorithms: `aionnich` vs `astra-sim-upstream`

## Scope and method

This review compares the checked-out revisions `aionnich@f4cbaddb` and
`astra-sim-upstream@518bd513`. Detailed packet behavior is not stored directly
in either top-level tree: it is supplied by gitlinks. The reviewed pins are
`aliyun/ns-3-alibabacloud@7e3cb5b8` for `aionnich` and
`astra-sim/astra-network-ns3@f764bed2` for upstream. Both pins were inspected in
temporary directories; neither source repository was initialized or modified.

“Reachable” below means selectable through the shipped ASTRA-sim ns-3 frontend
and then called on a packet path. Generic ns-3 queue disciplines and upstream's
separate analytical/HTSim frontends are not counted as implementations of the
RDMA algorithms requested here.

## Executive findings

1. **The congestion algorithms are a common code line, not independent new
   implementations.** HPCC, HPCC-PINT, DCQCN, DCTCP, ECN marking, PFC, static
   ECMP, and queue accounting use the same equations in both pins. Aionnich's
   changes do not improve their control laws.
2. **Genuine aionnich enhancements:** 64-bit sequence/rate-accounting state for
   flows beyond 4 GiB; NVSwitch/NVLS-aware forwarding; 64-bit egress queue
   counters; and runnable CSV telemetry for host/switch bandwidth, queue depth,
   QP rate, and CNP count.
3. **Incomplete in both:** no congestion-aware adaptive routing, no packet
   spraying, no coupled multipath controller, no explicit queue scheduler
   beyond strict control priority plus round-robin data queues, and no ECN/PFC
   closed-loop validation.
4. **Regressions in aionnich:** `GLOBAL_T` is always reset to `1`; 2.4/1.2-Tb/s
   INT line-rate encodings were removed while configurations use 1.6 Tb/s (also
   unencodable); ECN randomness moved to the obsolete RNG API; monitor unit
   labels are ambiguous; monitor callbacks assume nonempty filenames; and the
   NVSwitch-preference route construction is not an adaptive policy.
5. **Upstream integration defect:** its shipped backend sample config selects
   `CC_MODE 12`, but `RdmaHw` only dispatches modes 1, 3, 7, 8, and 10. Mode 12
   therefore runs at line rate with no rate-control handler and no INT mode.

## Algorithm and reachability matrix

| Area | Upstream | Aionnich | Runtime reachability / verdict |
|---|---|---|---|
| HPCC | `CC_MODE=3`; NORMAL INT | Same | Fully dispatched on every ACK. Same formula. Aionnich widens sequence state to 64 bit (real scale fix). |
| HPCC-PINT | `CC_MODE=10` | Same | Dispatched on sampled ACKs. Same formula and sampling. |
| DCQCN | `CC_MODE=1`, CNP-driven Mellanox state machine | Same | Fully reachable. Same formula/state transitions. Aionnich only adds CNP counters. |
| DCTCP | `CC_MODE=8` | Same | Reachable; ECN fraction and CWR state are unchanged. Not DCQCN. |
| ECN | RED-like byte-threshold marking at dequeue | Same equation | Reachable when `ENABLE_QCN=1`; Aionnich changes only RNG API. |
| PFC | Dynamic shared-buffer threshold with headroom and hysteresis | Same | Reachable per ingress priority. Aionnich removes upstream's configurable `HEADROOM_FACTOR` frontend support. |
| ECMP | Hop-shortest routing; MurmurHash3-like 5-tuple hash per switch | Same switch hash | Fully reachable, static per flow. |
| Multipath | Multiple equal-hop next hops; NIC and switches hash a QP/flow | Same, plus NVSwitch-specific NIC table | This is ECMP path diversity, not coupled transport multipath or packet spraying. |
| Adaptive routing | Link-down recomputation only | Same plus fixed NVSwitch preference | No load/queue/telemetry-driven route changes in either. |
| Rate control | Modes 1/3/7/8/10 | Same equations | Reachable only for those modes. Unknown modes silently retain line rate. |
| Queue management | Per-port/per-PG byte accounting; strict queue 0; RR data dequeue | Same, plus 64-bit egress counters | Functional but basic; no WRED/CoDel/DRR in the RDMA path. |
| Congestion signaling | CE at switch dequeue; receiver folds CE into ACK CNP; CNP/PFC priority 0 | Same | Fully reachable. CE is probabilistic by egress occupancy, PFC by ingress/shared occupancy. |
| Telemetry | INT/PINT plus FCT/PFC and queue log | INT/PINT plus FCT/PFC, host/switch BW, queue, QP rate and CNP CSV | Aionnich materially improves observability; its logs need unit/schema fixes. |

## Formulas, units, thresholds, and defaults

### HPCC (`CC_MODE=3`)

At hop `i`, two successive INT samples provide queue length `q` in bytes,
cumulative transmitted bytes `B`, timestamp `t` in ns, and line rate `C` in
bit/s. With `tau = delta(t)` seconds and flow window `W` in bytes:

```text
txRate_i = 8 * delta(B_i) / tau_i                         [bit/s]
u_i      = txRate_i/C_i + min(q_i,new,q_i,old)*Rmax/(C_i*W)
u_hat    = (u_hat*(baseRTT-dt) + u*dt) / baseRTT
c        = u_hat / U_target
R'       = R/c + AI, if c >= 1 or incStage >= MI_thresh
           R + AI, otherwise
R'       = clamp(R', MIN_RATE, Rmax)
```

The default target utilization is `0.95`, fast reaction is enabled, `AI` is
configuration-supplied (`50 Mb/s` in both representative configs), and
`MULTI_RATE` defaults true in code but is set to `0` in both representative
configs. In aggregate mode the maximum hop utilization controls one rate; in
multi-rate mode each hop has an `Rc` and the minimum proposed rate wins.

State transitions are first-ACK snapshot -> fast reactions for ACKs within the
current flight -> full update when ACK sequence passes `lastUpdateSeq`. Fast
reaction changes the applied rate but deliberately does not commit the
long-term `curRate`, utilization, or increment stage.

The law is identical. Aionnich's `snd_nxt`, ACK sequence, `lastUpdateSeq`, and
receiver expected sequence become `uint64_t`, preventing wrap after 2^32 bytes.
That is a genuine correctness enhancement for modern collective sizes.

### HPCC-PINT (`CC_MODE=10`)

PINT encodes a scalar utilization power in the INT header. An ACK is processed
with probability approximately `floor(65536*p)/65536`, using
`rand()%65536`. After decoding `U`:

```text
c  = U / U_target
R' = R/c + AI, if c >= 1 or incStage >= MI_thresh
     R + AI, otherwise
R' = clamp(R', MIN_RATE, Rmax)
```

Defaults are `PINT_PROB=1.0` and log base `1.05`. Both versions use the same
global C RNG, so sampling is not tied to ns-3 streams and is not a strong
reproducibility implementation. Aionnich fixes large-flow sequence width but
does not change the PINT control law.

### DCQCN (`CC_MODE=1`)

The receiver converts any accumulated CE bits to the CNP flag on ACK/NACK. On
CNP, the sender schedules/refreshes the Mellanox-style controller:

```text
alpha <- (1-g)*alpha + g*1      when CNP observed in interval
alpha <- (1-g)*alpha            otherwise
target <- current               unless CLAMP_TARGET_RATE is enabled
current <- max(MIN_RATE, current*(1-alpha/2))
```

Recovery performs five stages by code default (representative configs set one):
fast recovery averages current and target; active increase adds `RATE_AI`; then
hyper increase adds `RATE_HAI`, each capped at link rate. Relevant timer values
are numeric microseconds when converted by the frontend: representative values
are alpha interval `1 us`, decrease interval `4 us`, and RP timer `900 us`.
`EWMA_GAIN=0.00390625` (1/256), `RATE_AI=50 Mb/s`, `RATE_HAI=100 Mb/s`, and
`MIN_RATE=100 Mb/s` are the shipped representative settings. The code-level
initializer `double ewma_gain = 1/16` performs integer division and is therefore
**zero**, not 0.0625. A config that omits `EWMA_GAIN` disables alpha adaptation;
both representative configs avoid the defect by setting it explicitly.

The state machine and formulas are unchanged in aionnich. Its new per-QP CNP
counter is observational only.

### DCTCP (`CC_MODE=8`)

For one flight/batch, `F=min(1, markedACKs/batchPackets)` and
`alpha <- (1-g)*alpha + g*F`. On a marked ACK outside congestion-window-reduced
(CWR) state, `R <- max(MIN_RATE, R*(1-alpha/2))`, record `highSeq=snd_nxt`, and
enter CWR. ACK beyond `highSeq` exits CWR. An unmarked completed batch outside
CWR adds `DCTCP_RATE_AI` (default `1000 Mb/s`) up to link rate. Both versions are
identical except aionnich's 64-bit sequence boundaries.

### ECN marking and congestion signaling

For output queue occupancy `Q` in bytes:

```text
P(CE) = 0                                      Q <= Kmin
        Pmax*(Q-Kmin)/(Kmax-Kmin)              Kmin < Q <= Kmax
        1                                      Q > Kmax
```

Config map keys are line rates in bit/s. `KMIN_MAP`/`KMAX_MAP` values are in
decimal kB and are multiplied by `1000`; `PMAX_MAP` is a probability. Marking
occurs at dequeue, not enqueue. Queue 0 is never marked. The switch sets IPv4
ECN to CE (`3`); the receiver accumulates CE and returns it as the ACK CNP bit.
QCN/CNP, PFC, and optionally ACK/NACK use strict priority queue 0.

Upstream's sample thresholds include 400 Gb/s `800/3200 kB`, `Pmax=.2`, and a
2.4-Tb/s entry. Aionnich's representative config includes 400 Gb/s
`800/3200 kB`, but 200 Gb/s is unusually `300/1200 kB` with `Pmax=.8`, and it
adds 1.6-Tb/s `600/2400 kB`. These are configuration changes, not algorithm
changes. Missing a rate-map entry is caught by assertions during setup.

Aionnich replaces ns-3's `UniformRandomVariable` object with the legacy
`UniformVariable` API. That is a regression in stream control/reproducibility;
the probability equation itself is unchanged.

### PFC and buffer admission

All sizes are bytes. Base defaults in `SwitchMmu` are buffer `12 MiB`, reserved
per priority `4 KiB`, and resume offset `3 KiB`; the frontend overrides total
buffer with `BUFFER_SIZE * 1024*1024` (`32 MiB` in both representative configs).
For port `p`:

```text
T_pfc(p) = (buffer - totalHeadroom - totalReserved - sharedUsed)
           >> alphaShift[p]
shared(p,q) = max(ingressBytes(p,q)-reserve, 0)
pause iff not paused and (headroomBytes>0 or shared >= T_pfc)
resume iff paused and headroomBytes==0 and
           (shared==0 or shared+3KiB <= T_pfc)
drop iff packet+headroom > configuredHeadroom and
        packet+shared > T_pfc
```

This yields explicit RUNNING -> PAUSED -> RUNNING hysteresis per ingress
port/priority. Dynamic alpha shift is derived during setup from link delay/rate,
NIC rate, and headroom calculations. Upstream additionally exposes
`HEADROOM_FACTOR` (default 3) in its current frontend. Aionnich's parser does
not, so that upstream headroom sizing enhancement is lost.

### ECMP, multipath, and routing

Both frontends run unweighted BFS from every host, retain all equal-hop next
hops, and install them in host and switch tables. Link rate and delay affect BDP
and window calculations but **not path cost**. At a switch, a MurmurHash3-like
hash over source IP, destination IP, and transport ports modulo next-hop count
selects one output. Hosts similarly hash each QP modulo NIC choices. Thus a
flow is stable on one path; multiple flows can occupy multiple paths.

This is genuine ECMP but only a weak form of “multipath.” There is no subflow
state, coupled congestion window/rate, weighted next-hop selection, flowlet
switching, packet spraying, or reordering control. Upstream HTSim contains an
MPTCP type, but it is a different frontend and is not reachable from the ns-3
RDMA execution described here.

Aionnich extends BFS through node type 2 (NVSwitch), installs separate host
next-hop tables, and prefers NVSwitch parents on equal-hop paths. That enables
NVLS/intra-server traffic and is a real topology integration enhancement. It is
not adaptive routing: the decision is a fixed type preference and never reads
queue, ECN, PFC, bandwidth telemetry, or current path load. `active_ports` is
declared but unused.

Both versions recompute BFS and redistribute existing QPs after a configured
link-down event. That is failure recovery, not congestion adaptation. The
recomputed QP-to-NIC hash can move an active QP abruptly and has no explicit
ordering/state migration model.

### Queue scheduling and accounting

The RDMA data plane uses per-priority byte queues. Queue 0 is strict priority
for PFC/CNP and selected ACK/NACK traffic; ordinary QPs are chosen round-robin
subject to PFC pause and rate-controller `nextAvail`. Admission is always true
on egress; effective drops are determined by ingress shared/headroom accounting.
There is no RED queue discipline in this path—the RED-like behavior is only CE
mark probability.

Aionnich changes `egress_bytes` to 64 bit, a genuine long-run telemetry and
overflow fix. Ingress, headroom, threshold, and shared-used counters remain 32
bit, so simulations with a single queue above 4 GiB can still overflow. Its
NVSwitch “switch as host” transmit path duplicates scheduler logic and uses
packet-size heuristics (`60 < size < 9000`) to detect final sends; this is
fragile and incomplete for a configurable MTU or exactly-9000-byte last packet.

### Telemetry

In-band telemetry is common: HPCC carries per-hop timestamp (ns), transmitted
bytes, queue bytes, and a compact line-rate code; PINT carries encoded
utilization. Upstream exposes FCT, PFC events, and queue-length monitoring.
Aionnich adds scheduled CSV streams for:

- host and switch bandwidth (reported as Gbit/s),
- switch queue and total port occupancy (bytes),
- current per-QP rate (bit/s), and
- cumulative per-QP CNP count.

This is a genuine and useful enhancement, and the callbacks are connected from
the frontend. Limitations:

- CSV `time` is `Simulator::Now().GetTimeStep()` (ns in this build), while
  `MON_START`, `MON_END`, and intervals are scheduled with `MicroSeconds`; the
  schema does not state this mismatch.
- `PrintHostBW`/`PrintSwitchBw` compute `deltaBytes*8*1e6/interval`, so the
  interval is assumed microseconds, then divide by `1e9` for Gbit/s. A future
  time-resolution change would silently break it.
- Output is change-only, not a regular time series; zero-bandwidth/empty-queue
  intervals disappear.
- Setup opens and asserts all monitor filenames even though the string defaults
  are empty. A configuration omitting any monitor path aborts rather than
  disabling that monitor.
- Files are flushed on every row, materially increasing simulation cost.
- CNP counting increments for every CNP ACK regardless of selected mode; this
  is useful signaling telemetry but not “DCQCN events only.”

## Genuine enhancements

### Aionnich

- 64-bit sequence-space and controller batch boundaries eliminate the 4-GiB
  wrap defect across HPCC, HPCC-PINT, TIMELY, and DCTCP.
- 64-bit egress occupancy and byte counters improve long-run correctness.
- NVSwitch/NVLS node type, routing table separation, and host-like switch send
  path make intra-server GPU fabrics executable.
- Telemetry callbacks and CSV outputs expose queue, bandwidth, QP-rate, and CNP
  behavior that upstream does not provide end-to-end.
- Receiver route lookup explicitly falls back to the NVSwitch table rather than
  creating an empty normal-table entry.

### Upstream relative to aionnich

- Current upstream supports configurable `HEADROOM_FACTOR`; aionnich lacks the
  parser/wiring.
- Upstream preserves INT line-rate codes for 1.2 and 2.4 Tb/s and uses ns-3's
  stream-aware random-variable API.

## Incomplete implementations

- **Adaptive routing:** absent in both. No congestion metric reaches routing.
- **Multipath transport:** absent in the ns-3 RDMA frontend; only per-flow ECMP.
- **Unknown CC modes:** no parser validation or dispatch assertion. Modes other
  than 1/3/7/8/10 silently run without a controller.
- **TIMELY fast reaction:** `FastReactTimely` is an empty function despite ACKs
  taking that branch inside a flight.
- **PINT sampling:** uses global `rand`, not ns-3 RNG streams.
- **Queue management:** egress admission always returns true; there is no
  congestion-aware scheduler or AQM besides CE probability.
- **PFC model:** pause is per priority and has hysteresis, but no watchdog,
  deadlock recovery, pause-storm mitigation, or cable/ASIC validation model.
- **Telemetry-to-control:** new aionnich telemetry is write-only and cannot
  drive routing, rate, thresholds, or queue scheduling.
- **NVLS completion:** packet size is used as a completion proxy rather than QP
  sequence/remaining-byte state.

## Regressions and high-risk defects

1. **Aionnich ignores `GLOBAL_T`.** The parser reads the value and immediately
   assigns `global_t=1`. Its representative config says `GLOBAL_T 0`, but all
   QPs therefore use global maximum BDP/RTT instead of pair-specific values.
   This changes windows and HPCC queue normalization and is execution-reachable.
2. **Aionnich INT rate encoding regressed.** It removes upstream's 1.2- and
   2.4-Tb/s cases. Its own representative config uses 1.6 Tb/s, which neither
   table encodes. Unsupported rates map to the zero/sentinel line-rate entry,
   making HPCC utilization invalid (including possible division by zero).
3. **Upstream sample selects dead `CC_MODE 12`.** The sample configuration is
   build/run reachable, but no receive-ACK dispatch or INT mode handles 12.
4. **Aionnich monitor configuration is mandatory in practice.** Empty default
   filenames reach `fopen` followed by `assert`, turning an optional-looking
   feature into a startup failure for older configs.
5. **Aionnich loses `HEADROOM_FACTOR`.** Configs ported from current upstream
   silently ignore the key because the parser has no unknown-key rejection.
6. **Aionnich ECN stream reproducibility worsens** through the legacy random API.
7. **Routing semantic risk:** aionnich deletes previously collected equal-hop
   non-NVSwitch parents once an NVSwitch parent is observed. This changes ECMP
   fanout based on traversal/type rather than a documented metric and can reduce
   path diversity.
8. **Silent configuration errors in both:** the token parser has no final
   unknown-key error and no complete required-field validation. Misspellings can
   shift parsing or leave unsafe defaults.
9. **Broken DCQCN code default in both:** `double ewma_gain = 1/16` evaluates to
   zero. Only configs that explicitly set `EWMA_GAIN` obtain a working alpha
   filter.

## Bottom line

Aionnich is best characterized as an integration and scalability fork of the
same RDMA network-management algorithms. Its large-flow widths, NVSwitch path,
and telemetry are genuine improvements. It does **not** enhance HPCC/DCQCN/ECN/
PFC control mathematics and it does not add adaptive routing or true multipath.
Before treating results as comparable, fix or explicitly account for the
`GLOBAL_T` override, line-rate telemetry encoding, monitor startup assumptions,
headroom-factor loss, and mode validation. The first two can directly change
HPCC behavior and simulated flow completion times.

## Evidence map

- Aionnich frontend/configuration: `aionnich/astra-sim-alibabacloud/astra-sim/network_frontend/ns3/common.h`
- Aionnich representative defaults: `aionnich/astra-sim-alibabacloud/inputs/config/SimAI.conf`
- Aionnich pinned backend: gitlink `aionnich/ns-3-alibabacloud` at `7e3cb5b8`
- Upstream frontend reachability: `astra-sim-upstream/astra-sim/network_frontend/ns3/entry.h`
- Upstream build wiring: `astra-sim-upstream/build/astra_ns3/build.sh`
- Upstream pinned backend: gitlink `astra-sim-upstream/extern/network_backend/ns-3` at `f764bed2`
- Backend algorithm files in both pins: `src/point-to-point/model/rdma-hw.cc`,
  `switch-mmu.cc`, `switch-node.cc`, `qbb-net-device.cc`,
  `rdma-queue-pair.h`, and `src/network/utils/int-header.{h,cc}`
