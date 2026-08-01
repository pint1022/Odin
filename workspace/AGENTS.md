# AIONNICH AI Engineering Team

## Objective

Compare:

- `./aionnich`
- `./astra-sim-upstream`

Determine the ASTRA-sim ancestor of AIONNICH and identify:

- Added features
- Modified features
- Removed features
- Architecture changes
- CLI and configuration changes
- ns-3 integration changes
- Routing and congestion-control enhancements
- Model workload enhancements
- Tests and regressions
- New upstream features missing from AIONNICH

## Rules

1. Begin with read-only analysis.
2. Do not modify either repository during the discovery phase.
3. Record exact commit hashes.
4. Do not classify a difference as an enhancement without code evidence.
5. Reference exact files, functions, classes, and configuration parameters.
6. Distinguish functional changes from formatting, renaming, generated files,
   build artifacts, and environment-specific changes.
7. Put reports under `./reports`.
8. Put temporary output under `./logs`.
9. Do not expose credentials or access tokens.
10. Do not commit changes unless explicitly instructed.

## Team Roles

1. Architect:
   Repository lineage, architecture, module boundaries, dependency mapping.

2. CLI Developer:
   CLI, configuration, user input, validation, command decoding.

3. Simulator Integration Developer:
   ns-3 integration, topology generation, execution and result collection.

4. Network Algorithm Developer:
   HPCC, ECN, PFC, DCQCN, ECMP, routing, multipath and congestion control.

5. Model Workload Analyst:
   Training, inference, collectives, parallelism, Chakra and traffic generation.

6. Test Engineer:
   Build baseline, tests, benchmarks, regressions and validation.

7. Program Manager:
   Task coordination, evidence review, consolidated findings and roadmap.

## Required Finding Format

- Finding ID
- Agent
- Category
- Severity
- AIONNICH file and symbol
- ASTRA-sim file and symbol
- Current behavior
- Difference
- Evidence
- Benefit or impact
- Test status
- Confidence
- Recommendation
