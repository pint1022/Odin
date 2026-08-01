# CLI and Configuration Comparison: AIONNICH vs. ASTRA-sim Upstream

## Scope and baseline

This is a static, read-only comparison of AIONNICH commit `f4cbaddb4ebd2e8ae4c3f69da624694dc68d74bc` and ASTRA-sim upstream commit `518bd513ae110428cd62eb60efc0f3993fd53c70`. “Upstream” below means that exact checkout, not the historical ASTRA-sim 1.0 ancestor named by AIONNICH's README. No source repository was modified.

AIONNICH is not a drop-in CLI extension of this upstream revision. It exposes a different product surface: `SimAI_analytical`, `SimAI_simulator`, and `SimAI_phynet`, plus a separate Vidur Python application. Upstream exposes analytical congestion-aware/unaware binaries, an ns-3 executable, and HTSim, all around a mostly common ASTRA-sim argument/configuration contract.

## Executive comparison

| Area | AIONNICH | ASTRA-sim upstream | Assessment |
|---|---|---|---|
| Entry points | Handwritten analytical CLI (`AnalyticalAstra.cc`), physical-network getopt CLI (`SimAiMain.cc`), ns-3 wrapper supplied through the copied `ns-3-alibabacloud` tree, build dispatcher, Vidur Python main | Congestion-aware and congestion-unaware analytical mains, ns-3 main, HTSim main, backend build scripts | AIONNICH adds domain-specific and inference entry points, but loses a uniform simulator interface. |
| CLI parsing | Manual string loop and `stoi`/`stof`; physical mode uses `getopt`; ns-3 usage documented as short flags | Shared typed `cxxopts` parser for analytical/HTSim; ns-3 `CommandLine` parser | AIONNICH is simpler for SimAI users but substantially less robust and less self-describing. |
| Core configuration | Workload-oriented CLI; legacy plaintext workload; whitespace key/value ns-3 `.conf`; topology text; derived bandwidth settings | Chakra ET workload; JSON system, remote-memory and communicator-group configs; YAML analytical network; JSON logical topology for ns-3; optional TOML logging | AIONNICH adds training-specific input semantics but removes separation/composability of several upstream configs. |
| Validation/errors | Mostly missing-value checks by omission, uncaught numeric conversions, limited enum validation, warnings for malformed workload headers | Parser catches option errors; typed decoding; explicit file/readability checks in important paths; semantic validation is still incomplete | Clear AIONNICH regression. |
| Defaults | Numerous in-code and derived defaults, some uninitialized fields; automatic result naming | Explicit CLI defaults for optional cross-backend controls; configuration members have local defaults | AIONNICH improves convenience but makes runs less predictable. |
| Automation | Unified build dispatcher, stable `bin/` links, generated result names, CSV/report output, Vidur CLI/config snapshots and config exploration | Backend-specific build/run scripts and regression template | AIONNICH enhancement, with portability/reproducibility caveats. |
| Compatibility | Explicit defaults for older SimAI workload headers; accepts several GPU spellings | Stable common options across analytical, ns-3, and HTSim; `comm-group=empty` compatibility convention | AIONNICH preserves its own legacy text format, but breaks current upstream CLI/config compatibility. |

## Entry points, commands, and arguments

### AIONNICH

`astra-sim-alibabacloud/astra-sim/network_frontend/analytical/AnalyticalAstra.cc:68` is the analytical executable. It calls singleton `UserParam::parse`, sets `ModeType::ANALYTICAL`, constructs one `Sys`, and runs `AnaSim`. The public README documents:

```text
SimAI_analytical -w WORKLOAD -g GPUS -g_p_s GPUS_PER_SERVER -r RESULT ...
```

`UserParam::parse` in `astra-sim-alibabacloud/astra-sim/system/AstraParamParse.hh:96` accepts `-w/--workload`, repeatable `-g/--gpus`, `-r/--result`, `-r_f/--result_folder`, GPU/NIC topology and bandwidth inputs, visualization, four overlap ratios, GPU/NIC types, and report language. These options directly represent training concerns absent from upstream's generic CLI.

`astra-sim-alibabacloud/astra-sim/network_frontend/phynet/SimAiMain.cc:112` is the physical-network/MPI executable. Its separate `user_param_prase` uses `getopt` for workload, GPUs, communication scale, thread count, and RDMA GID index. This parser is not shared with analytical mode and already differs in names and defaults.

The checked-in AIONNICH tree does not contain the copied `extern/network_backend/ns3-interface` source from which `SimAI_simulator` is built. `scripts/build.sh:17-25` copies the sibling `ns-3-alibabacloud` repository into that location and creates a symlink named `bin/SimAI_simulator`. The README documents its separate short-option interface (`-t`, `-w`, `-n`, `-c`). Consequently, the ns-3 command contract cannot be built from the AIONNICH repository alone and is version-dependent on an external sibling checkout.

`scripts/build.sh` is the user-facing build dispatcher: `-c/--compile` and `-l/--clean`, followed by `ns3`, `phy`, or `analytical`. The nested `astra-sim-alibabacloud/build.sh` also advertises `-lr/--clean-result`; the top-level script's help advertises `-lr` but its case statement does not implement it. Unknown commands fall into help and exit successfully.

Finally, `vidur-alibabacloud/vidur/main.py:6` adds an inference-simulation entry point. It dynamically derives a large argparse CLI from nested dataclasses and runs request scheduling. Config-optimizer, profiler, report, and dashboard modules provide additional specialized Python entry points. These are genuine product additions, although they are adjacent orchestration rather than replacements for the C++ simulator CLI.

### Upstream

Upstream analytical congestion-aware and congestion-unaware mains use `CmdLineParser`; HTSim extends that same parser with `--htsim-proto`. The shared options in `astra-sim/network_frontend/analytical/common/CmdLineParser.cc:18` are:

- required in practice: `--workload-configuration`, `--system-configuration`, `--remote-memory-configuration`, `--network-configuration`;
- optional: `--comm-group-configuration=empty`, `--logging-configuration=empty`, `--logging-folder=log`, `--num-queues-per-dim=1`, `--compute-scale=1`, `--comm-scale=1`, `--injection-scale=1`, and `--rendezvous-protocol=false`.

The ns-3 main (`AstraSimNetwork.cc:245`) retains the same principal configuration names and adds `--logical-topology-configuration`. HTSim additionally recognizes an `--htsim_opts` delimiter and forwards the remaining argv segment to HTSim. This produces much stronger consistency across backends than AIONNICH.

One upstream defect is worth preserving in the comparison: `--compute-scale` is defined but neither analytical main reads it. Also, `allow_unrecognised_options()` makes misspelled/unknown options easy to ignore, apparently to permit HTSim forwarding. Thus upstream parsing is better structured, not fully strict.

## Configuration formats and user-input decoding

Upstream deliberately separates concerns:

- workload: per-rank Chakra execution traces named `<prefix>.<rank>.et`; `Workload.cc:28-46` checks existence versus readability before constructing `ETFeeder`;
- system: JSON parsed by nlohmann JSON in `Sys::initialize_sys` (`Sys.cc:312`), including scheduling, collective implementation, delays, roofline, tracing, and memory tracking;
- communicator groups: JSON, or the sentinel string `empty`;
- analytical network: YAML parsed by the analytical network library;
- remote memory: JSON;
- ns-3 logical topology: JSON, while the ns-3 packet-network configuration remains backend-specific;
- logging: optional TOML/pre-TOML infrastructure through `LoggerFactory`/spdlog setup.

AIONNICH's core simulation path instead passes most behavior directly into an enlarged `Sys` constructor. Its workload is a custom line-oriented text format. `Workload::initialize_workload` (`Workload.cc:1145`) decodes the first whitespace-tokenized header (parallelism policy plus `model_parallel_NPU_group:`, `ep:`, `pp:`, `vpp:`, `ga:`, `all_gpus:`, checkpoints, and `pp_comm`) and parses subsequent layer records. This is a major enhancement for direct LLM training representation, but it is positional and fragile: several branches read `tokens[i+1]` without bounds checks and call `stoi` directly.

The AIONNICH ns-3 configuration is a large whitespace-separated key/value file (`inputs/config/SimAI.conf`). `ReadConf` in `network_frontend/ns3/common.h:460` loops with formatted extraction and a long `if/else` chain. Unknown keys have no diagnostic and stream/open failure is not checked before parsing. Values combine integers, floats, rates with units, paths, and count-prefixed maps without a schema or version marker. The topology is a second custom text input. This format makes experimentation easy to edit, but is less safely decoded and less tool-friendly than JSON/YAML.

The README advertises a `-busbw example/busbw.yaml` analytical option, but `UserParam::parse` contains neither `-busbw` nor YAML loading. The implementation now computes bandwidth from `-nv`, `-nic`, `-n_p_s`, GPU/NIC type, and collective shape (`Layer.cc:980-1029`). The documented command therefore fails as an unknown argument: a concrete documentation/CLI regression.

Vidur is better structured. `flat_dataclass.create_from_cli_args` (`vidur/config/flat_dataclass.py:88`) recursively flattens nested dataclasses into argparse flags; primitives are typed, lists use `nargs='+'`, dictionaries/non-primitive lists use `json.loads`, booleans use `BooleanOptionalAction`, required fields are inferred from missing defaults, and help displays defaults. `SimulationConfig.__post_init__` writes a JSON snapshot to `<output_dir>/config.json`, giving experiments an auditable resolved configuration. The downside is a huge flat namespace, reliance on assertions for several invariants, and no exception wrapper around JSON/value/path failures.

## Validation, defaults, and error handling

Upstream catches `cxxopts::OptionException` both while parsing and retrieving values and prints a scoped error before exiting. Typed conversion covers integers, doubles, booleans, and `HTSimProto`. Missing required-in-practice options are detected only when retrieved, rather than declared required. System JSON validates selected enums and panics on unknown scheduling/optimization values; workload paths distinguish missing and unreadable files. JSON/YAML exceptions are not consistently normalized, so upstream still exposes raw exceptions in some malformed-file cases.

AIONNICH's `UserParam` returns `1` for help, any unknown option, or invalid language; the analytical main prints only a one-line help hint and returns `-1`. There is no specific “unknown option” or “missing value” message. If an option lacks a following token, it is silently left unchanged. `stoi`/`stof` exceptions are uncaught. GPU type silently becomes `GPUType::NONE`; `nic_type` is unrestricted; overlap ratios and counts have no range checks.

Several defaults are unsafe or contradictory:

- help says GPUs default to 1, while analytical `gpus` defaults to an empty vector and `AnalyticalAstra.cc:76` dereferences `param->gpus[0]`;
- `NetWorkParam::gpus_per_server`, `nics_per_server`, `nvswitch_num`, counts, and `gpu_type` have no constructor/default initializers, yet parsing and derived result naming use them;
- automatic result naming divides by parsed `tp * pp` and by `dp * mbs`; an ordinary workload filename without the expected encoded tokens leaves these at zero;
- physical mode's constructor defaults to 8 GPUs although its help says 1, and any `-g <= 8` is silently coerced to 8;
- `comm_scale` is an `int` in both AIONNICH parameter structs, but physical parsing uses `stof`, truncating fractional input;
- help returns an error status instead of success.

AIONNICH workload decoding does include useful compatibility defaults (`Workload.cc:48-56`): older headers missing `ep`, `pp`, `vpp`, `ga`, or `all_gpus` receive value 1 and missing `pp_comm` receives 0. It warns when the decoded parallelism combination is inconsistent. The check is only a warning and only rank zero emits it; malformed positional data may already have caused an exception or out-of-bounds access.

## Experiment automation

AIONNICH materially improves end-user automation:

- `scripts/build.sh` builds three modes and creates stable `bin/SimAI_*` links;
- analytical runs derive descriptive result names from workload filename metadata and can group them under a result folder;
- workload code emits detailed, end-to-end, utilization, and localized reports;
- Vidur persists the resolved config and includes configuration exploration, capacity search, profiling, metrics extraction, Pareto generation, and dashboards;
- `retry_tail.py` supplies operational retry/log-tail behavior.

These improvements carry reproducibility and portability risks. Build scripts copy an entire sibling ns-3 working tree, delete the destination, depend on fixed source output paths, and the nested build flow creates `/etc/astra-sim` directories. Generated result naming depends on a filename convention rather than a parsed manifest. Upstream automation is less ambitious but its example scripts explicitly bind the four core config paths, its regression template runs a fixed workload/system/network/memory tuple, and each backend has focused build scripts.

## Backward compatibility

AIONNICH's custom workload parser consciously supports older AIONNICH/AICB headers through defaults and tolerates `pp_comm` with or without a colon. GPU names accept upper- and lower-case spellings. Those are exact compatibility enhancements.

Against this upstream revision, compatibility regresses sharply. AIONNICH analytical mode does not accept upstream's `--system-configuration`, `--network-configuration`, `--remote-memory-configuration`, `--comm-group-configuration`, queue/scaling/logging/rendezvous options, or Chakra ET filename convention. It does not expose upstream HTSim. Its custom text workload, topology, and ns-3 `.conf` are not interchangeable with upstream's JSON/YAML/ET set. Scripts or experiment manifests written for current upstream therefore require translation, not merely a binary rename.

## Findings

### CLI-001 — Domain-specific analytical CLI and automatic experiment identity

- **Finding ID:** CLI-001
- **Agent:** Front-End and CLI Developer
- **Category:** Enhancement / experiment automation
- **Severity:** Medium
- **AIONNICH file and symbol:** `AstraParamParse.hh`, `UserParam::parse`; `AnalyticalAstra.cc`, `main`
- **ASTRA-sim file and symbol:** `CmdLineParser.cc`, `CmdLineParser::define_options`; analytical `main`
- **Current behavior:** AIONNICH accepts GPU/server/NIC/bandwidth/overlap/language parameters and derives a result name; upstream accepts generic component configuration paths and simulation scales.
- **Difference:** AIONNICH elevates common LLM-training knobs to first-class CLI inputs and automates result organization.
- **Evidence:** `AstraParamParse.hh:96-249`; upstream `CmdLineParser.cc:18-42`.
- **Benefit or impact:** Faster parameter sweeps and fewer hand-authored system files, at the cost of a less composable and less reproducible interface.
- **Test status:** Static inspection only.
- **Confidence:** High.
- **Recommendation:** Retain the domain flags, but resolve them into a versioned config manifest and print/write the complete effective configuration before execution.

### CLI-002 — Unsafe handwritten CLI parser and defaults

- **Finding ID:** CLI-002
- **Agent:** Front-End and CLI Developer
- **Category:** Regression / validation / defaults / error handling
- **Severity:** Critical
- **AIONNICH file and symbol:** `AstraParamParse.hh`, `NetWorkParam`, `UserParam::UserParam`, `UserParam::parse`
- **ASTRA-sim file and symbol:** `CmdLineParser.cc`, `parse`; `CmdLineParser.hh`, `get<T>`
- **Current behavior:** AIONNICH silently ignores missing values, returns a generic error for unknown input, leaves important members uninitialized, and exposes uncaught conversions/division-by-zero paths. Upstream uses typed decoding and catches parser errors.
- **Difference:** The new parser reduces dependency/boilerplate but loses type-safe, diagnosable behavior.
- **Evidence:** `AstraParamParse.hh:39-59, 72-94, 96-249`; `AnalyticalAstra.cc:69-77`; upstream `CmdLineParser.cc:45-55` and `CmdLineParser.hh:42-51`.
- **Benefit or impact:** Invalid or incomplete experiments can crash, generate undefined topology values, or produce misleading outputs.
- **Test status:** Static inspection; failure paths were not executed.
- **Confidence:** High.
- **Recommendation:** Use a shared parser, mark required arguments, initialize every field, validate positive counts/ranges, catch conversions, and return conventional exit codes.

### CLI-003 — Upstream backend-neutral command/config contract removed

- **Finding ID:** CLI-003
- **Agent:** Front-End and CLI Developer
- **Category:** Regression / entry points / compatibility
- **Severity:** High
- **AIONNICH file and symbol:** `AnalyticalAstra.cc::main`; `SimAiMain.cc::main`; `scripts/build.sh`
- **ASTRA-sim file and symbol:** analytical mains, `HTSimMain.cc::main`, `AstraSimNetwork.cc::parse_args`
- **Current behavior:** Upstream backends share workload/system/network/memory/comm-group controls; AIONNICH modes each expose a distinct interface and HTSim is absent.
- **Difference:** Backend interchangeability and upstream script compatibility are lost.
- **Evidence:** Upstream `CmdLineParser.cc:18-42`, `AstraSimNetwork.cc:245-272`, `HTSimMain.cc:17-38`; AIONNICH `AnalyticalAstra.cc:68-75`, `SimAiMain.cc:68-109`.
- **Benefit or impact:** Users cannot switch backend while retaining one experiment manifest; porting upstream experiments requires format and command translation.
- **Test status:** Static inspection only.
- **Confidence:** High.
- **Recommendation:** Define one shared SimAI command schema with backend subcommands and provide an upstream-compatibility alias layer.

### CLI-004 — Rich custom training workload decoding with legacy defaults

- **Finding ID:** CLI-004
- **Agent:** Front-End and CLI Developer
- **Category:** Enhancement with robustness regression / user-input decoding / compatibility
- **Severity:** High
- **AIONNICH file and symbol:** `Workload.cc`, constructor and `Workload::initialize_workload`
- **ASTRA-sim file and symbol:** `Workload.cc`, constructor and `ETFeeder` path
- **Current behavior:** AIONNICH decodes model/expert/pipeline parallelism, gradient accumulation, checkpoints, and pipeline communication from readable text; upstream consumes per-rank Chakra ET traces.
- **Difference:** AIONNICH represents more training semantics directly and defaults missing legacy header fields, but parsing is unchecked and positional.
- **Evidence:** AIONNICH `Workload.cc:48-56, 1145-1287`; upstream `Workload.cc:28-54`.
- **Benefit or impact:** Better AICB integration and backward compatibility; malformed input can throw or access beyond token bounds.
- **Test status:** Static inspection only.
- **Confidence:** High.
- **Recommendation:** Publish a versioned grammar/schema, validate token arity and numeric ranges before indexing, and emit line/column diagnostics.

### CLI-005 — ns-3 configuration is broad but schema-less

- **Finding ID:** CLI-005
- **Agent:** Front-End and CLI Developer
- **Category:** Enhancement and regression / configuration format / validation
- **Severity:** High
- **AIONNICH file and symbol:** `network_frontend/ns3/common.h`, `ReadConf`; `inputs/config/SimAI.conf`
- **ASTRA-sim file and symbol:** `AstraSimNetwork.cc`, `parse_args`; examples under `examples/network/ns3`
- **Current behavior:** AIONNICH exposes extensive QCN/PFC/rate/monitoring controls through a text `.conf`; upstream uses a smaller top-level CLI and structured logical topology/config artifacts.
- **Difference:** AIONNICH exposes many practical network knobs but has no schema, unknown-key diagnostics, required-key tracking, or reliable open/parse failure reporting.
- **Evidence:** `common.h:460-670`; `SimAI.conf:1-65`.
- **Benefit or impact:** Powerful tuning surface, but typos and partial files can silently retain global defaults and invalidate experiments.
- **Test status:** Static inspection only.
- **Confidence:** High.
- **Recommendation:** Move to versioned YAML/JSON with unknown-key rejection, units, required fields, ranges, and a `--validate-config` dry run.

### CLI-006 — Vidur inference CLI and configuration automation added

- **Finding ID:** CLI-006
- **Agent:** Front-End and CLI Developer
- **Category:** Enhancement / entry point / automation
- **Severity:** Medium
- **AIONNICH file and symbol:** `vidur/main.py::main`; `vidur/config/flat_dataclass.py::create_from_cli_args`; `SimulationConfig`
- **ASTRA-sim file and symbol:** No counterpart.
- **Current behavior:** Nested typed dataclasses generate argparse options and persist resolved JSON; additional optimizer/profiler/report entry points automate inference experiments.
- **Difference:** AIONNICH adds an end-to-end multi-request inference configuration plane.
- **Evidence:** `main.py:6-14`; `flat_dataclass.py:88-136`; `config.py:746-766`.
- **Benefit or impact:** Strong discoverability and experiment auditability; flat flag volume and assertion-based validation remain concerns.
- **Test status:** Static inspection only.
- **Confidence:** High.
- **Recommendation:** Keep config snapshots, add config-file ingestion/overrides and explicit cross-field validation with user-facing errors.

### CLI-007 — Documentation and build-command drift

- **Finding ID:** CLI-007
- **Agent:** Front-End and CLI Developer
- **Category:** Regression / commands / error handling
- **Severity:** Medium
- **AIONNICH file and symbol:** `README.md` analytical example; `AstraParamParse.hh::parse`; `scripts/build.sh` dispatch
- **ASTRA-sim file and symbol:** Backend example run scripts and build scripts.
- **Current behavior:** README documents `-busbw`, which the parser rejects; top-level build help documents `-lr`, which it does not dispatch; unknown build commands print help and succeed.
- **Difference:** User-facing contracts do not match implementation.
- **Evidence:** README “Use SimAI-Analytical”; `AstraParamParse.hh:96-173`; `scripts/build.sh:67-76`.
- **Benefit or impact:** Copy-paste quick starts fail or appear to succeed without taking the requested action.
- **Test status:** Static command-path inspection only.
- **Confidence:** High.
- **Recommendation:** Add CLI smoke tests generated from README examples and make unsupported commands exit nonzero.

### CLI-008 — External copied ns-3 source weakens reproducibility

- **Finding ID:** CLI-008
- **Agent:** Front-End and CLI Developer
- **Category:** Regression / entry point / automation
- **Severity:** High
- **AIONNICH file and symbol:** `scripts/build.sh::compile(ns3)`
- **ASTRA-sim file and symbol:** `astra-sim/network_frontend/ns3/AstraSimNetwork.cc::main`; `build/astra_ns3/build.sh`
- **Current behavior:** AIONNICH deletes and recopies a sibling ns-3 tree before building the public simulator binary; upstream checks in its ASTRA-sim ns-3 entry point and uses a submodule/backend build.
- **Difference:** The effective AIONNICH CLI depends on external mutable source not present in the analyzed tree.
- **Evidence:** `scripts/build.sh:5-10, 16-25`; absence of `astra-sim-alibabacloud/extern/network_backend/ns3-interface` in this checkout.
- **Benefit or impact:** A commit hash alone is insufficient to reproduce or audit the ns-3 command surface.
- **Test status:** Static inspection; external sibling source intentionally not analyzed as part of either requested repository.
- **Confidence:** High.
- **Recommendation:** Pin the ns-3 dependency, record its commit in build/run metadata, and keep the CLI adapter in the main repository.

## Priority recommendations

1. Fix CLI-002 first: initialization, required arguments, numeric/range checks, error messages, and exit statuses are correctness issues.
2. Establish one versioned, backend-neutral experiment schema and add compatibility aliases for upstream arguments.
3. Add schema validation and a no-run validation command for workload, topology, network, and inference configs.
4. Reconcile README/build help with executable behavior and exercise every published command in CI.
5. Preserve AIONNICH's strongest additions—training semantics, automatic run artifacts, and Vidur config snapshots—while recording a complete resolved manifest and all dependency commit hashes per experiment.
