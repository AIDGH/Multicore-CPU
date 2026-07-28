# Ehsan Infrastructure Handoff

## Status and responsibility boundary

This document records the current repository state and the team responsibility
transfer after acceptance of the multicore interconnect shell. It supplements
the original assignment in `project_1_task_assignment.md`; it does not alter
the university specification in `project_1_exact_text.md`.

Ehsan's assigned scope is complete and accepted through:

- repository and active RTL structure
- preservation of the frozen `Hw6/` baseline
- migration of the baseline CPU into `rtl/core/`
- CPU variable-latency data request/response handling and memory stalls
- 32-bit byte-addressed CPU data requests
- shared definitions and interface documentation
- Bash regression infrastructure
- the two-requester transaction-holding round-robin arbiter
- the shared-bus transaction and snoop-routing shell
- the shared line-memory endpoint
- bus-to-memory integration
- the two-cache-endpoint `multicore_interconnect_top`
- Icarus compatibility and warning cleanup for the accepted regressions

> Ehsan's implementation responsibility ends at the accepted
> `multicore_interconnect_top` boundary.

Ehsan has no remaining obligation to implement, connect, debug, validate, or
finalize the production cache, MESI behavior, atomic instructions, reservation
logic, CPU extensions, or final dual-core system. He may answer questions
about the accepted infrastructure, but no further implementation is assigned
to him. The final multicore CPU project is not yet complete.

## Accepted, regression-protected infrastructure

The accepted production boundary consists of:

- `rtl/common/mc_defs.svh`
- `rtl/core/cpu_core.v`
- `rtl/bus/rr_arbiter.sv`
- `rtl/bus/shared_bus.sv`
- `rtl/memory/shared_memory.sv`
- `rtl/top/multicore_interconnect_top.sv`

These modules currently pass the accepted regression suite and form the
regression-protected infrastructure boundary. They must not be redesigned to
accommodate a preferred cache or atomic implementation. A change is permitted
only when a demonstrated interface defect blocks the assigned cache or atomic
integration. Every such change must:

1. be explained in its pull request;
2. include a self-checking regression that reproduces the problem;
3. preserve every existing regression;
4. receive team review before merge.

Minimal CPU changes demonstrably required to implement Shahab's assigned ISA
features follow the same rule: preserve baseline behavior, justify each
contract change, and add regression coverage.

## Current shared types and constants

`rtl/common/mc_defs.svh` defines the current shared namespace:

- `MC_ADDR_WIDTH = 32`
- `MC_WORD_WIDTH = 32`
- `MC_LINE_WIDTH = 128`
- `MC_LINE_BYTES = 16`
- `MC_LINE_OFFSET_BITS = 4`
- `MC_LINE_ID_WIDTH = 28`
- `MC_CORE_ID_WIDTH = 1`
- `mc_mem_op_t`: `MC_MEM_LOAD`, `MC_MEM_STORE`, `MC_MEM_LR`, `MC_MEM_SC`,
  and `MC_MEM_AMOADD`
- `mc_bus_txn_t`: `MC_BUS_RD`, `MC_BUS_RDX`, and `MC_BUS_WRITEBACK`
- `mc_line_mem_op_t`: `MC_LINE_READ` and `MC_LINE_WRITE`
- `mc_resp_status_t`: `MC_RESP_OK`, `MC_RESP_SC_SUCCESS`, and
  `MC_RESP_SC_FAILURE`

The operation and response enums reserve shared meanings, but the active
`cpu_core` production ports do not yet carry `mc_mem_op_t` or
`mc_resp_status_t`. Their use in `tb/mocks/` is test-only and must not be
mistaken for an already accepted production CPU/cache interface.

## Updated ownership

### Arad: production cache and coherence

Arad retains the original cache/coherence scope and owns:

- production private L1 cache RTL;
- direct-mapped organization with 16-byte lines;
- write-back and write-allocate behavior;
- MESI states, transitions, and transient behavior;
- CPU-to-cache handshake integration;
- cache-to-interconnect endpoint integration;
- `BusRd` and `BusRdX` generation and handling;
- snoop acknowledgement, invalidation, and clean shared-line reporting;
- dirty-line write-back and dirty-peer data intervention;
- replacement of testbench/mock endpoints with real L1 instances;
- cache-side self-checking regressions;
- cache, MESI, and snoop-related full-system debugging.

Arad must connect to the accepted boundaries below. Changes to Ehsan's bus,
memory, arbiter, or interconnect require the defect/regression/review process
defined above.

### Shahab: ISA, atomics, reservations, and architectural validation

Shahab retains the original ISA/atomic/testing scope and owns:

- `cpuid` decode, result generation, and validation;
- core-ID propagation;
- `lr.w` decode and execution;
- reservation creation, exact word address, and valid-state storage;
- `sc.w` success/failure behavior and clearing after every SC attempt;
- remote reservation invalidation;
- local conflicting-store reservation behavior;
- `amoadd.w` decode and execution;
- indivisible atomic read-modify-write behavior;
- exactly one architectural completion and correct register write-back;
- delayed-memory and cache-stall interaction;
- atomic and reservation regressions;
- atomic, ISA, reservation, and register-write-back debugging.

Shahab must integrate these features with the accepted CPU/cache contracts.
Changes to Ehsan's bus, memory, arbiter, or interconnect require the same
defect/regression/review process.

### Arad and Shahab jointly: remaining project finalization

Arad and Shahab jointly own all remaining final integration:

- create the final top-level with two CPUs and two production L1 caches;
- connect both caches to `multicore_interconnect_top`;
- assign core IDs 0 and 1;
- connect coherence invalidations to reservation logic;
- implement dirty cache-to-cache intervention or the required dirty
  write-back sequence;
- resolve the temporary dirty-peer unsupported behavior;
- connect `cpuid`, `lr.w`, `sc.w`, and `amoadd.w`;
- create multicore assembly/instruction programs and full-system tests;
- resolve cache/atomic interactions and perform final integration debugging;
- collect performance measurements;
- prepare final architecture and timing diagrams;
- complete the final report and demonstration;
- merge the reviewed, completed system from `develop` into `main`.

None of these tasks remains assigned to Ehsan. Arad and Shahab may divide the
joint list between themselves, but they must record their chosen division
before final integration begins.

## Arad connection guide

### Active CPU-to-L1 boundary

The active module is `cpu_core`. Its data-side ports are:

| Direction relative to `cpu_core` | Exact port | Width | Meaning |
|---|---|---:|---|
| output | `data_req_valid` | 1 | Pending ordinary load/store request |
| input | `data_req_ready` | 1 | Request accepted with `data_req_valid` |
| output | `data_req_addr` | 32 | Byte address |
| output | `data_req_write` | 1 | `0` load, `1` store |
| output | `data_req_wdata` | 32 | Store word |
| input | `data_rsp_valid` | 1 | Final operation completion |
| input | `data_rsp_rdata` | 32 | Load word |
| input | `data_rsp_error` | 1 | Terminal data-operation error |

The real L1 must accept a request only on
`data_req_valid && data_req_ready`. While waiting for acceptance, the CPU holds
`data_req_addr`, `data_req_write`, and `data_req_wdata` stable. After
acceptance, the CPU permits one outstanding request and stalls architectural
progress until `data_rsp_valid`. A successful load is written back exactly
once. A store completes without register write-back. The current CPU enters
`MEM_ERROR_HALT` on `data_rsp_valid && data_rsp_error` and remains stalled
until reset.

The CPU address is a 32-bit byte address. The L1 owns word selection within a
line and must use the aligned line address
`{data_req_addr[31:4], 4'b0000}` for the interconnect. The current active CPU
boundary represents only ordinary loads and stores; its extension for atomics
is a joint Arad/Shahab integration point.

### Real L1-to-interconnect boundary

The shell's system inputs are `clk` and active-high `rst`. Its exact cache
ports are:

| Direction relative to `multicore_interconnect_top` | Endpoint 0 | Endpoint 1 |
|---|---|---|
| input | `cache0_req_valid` | `cache1_req_valid` |
| output | `cache0_req_ready` | `cache1_req_ready` |
| input `mc_bus_txn_t` | `cache0_req_txn` | `cache1_req_txn` |
| input `[MC_ADDR_WIDTH-1:0]` | `cache0_req_line_addr` | `cache1_req_line_addr` |
| input `[MC_LINE_WIDTH-1:0]` | `cache0_req_wdata` | `cache1_req_wdata` |
| output | `cache0_rsp_valid` | `cache1_rsp_valid` |
| output `[MC_LINE_WIDTH-1:0]` | `cache0_rsp_data` | `cache1_rsp_data` |
| output | `cache0_rsp_shared` | `cache1_rsp_shared` |
| output | `cache0_rsp_error` | `cache1_rsp_error` |
| output | `cache0_snoop_valid` | `cache1_snoop_valid` |
| output `mc_bus_txn_t` | `cache0_snoop_txn` | `cache1_snoop_txn` |
| output `[MC_ADDR_WIDTH-1:0]` | `cache0_snoop_line_addr` | `cache1_snoop_line_addr` |
| output | `cache0_snoop_requester_id` | `cache1_snoop_requester_id` |
| input | `cache0_snoop_rsp_valid` | `cache1_snoop_rsp_valid` |
| input | `cache0_snoop_rsp_present` | `cache1_snoop_rsp_present` |
| input | `cache0_snoop_rsp_dirty` | `cache1_snoop_rsp_dirty` |
| input | `cache0_snoop_rsp_data_valid` | `cache1_snoop_rsp_data_valid` |
| input `[MC_LINE_WIDTH-1:0]` | `cache0_snoop_rsp_data` | `cache1_snoop_rsp_data` |

`multicore_interconnect_top` contains one `shared_bus` and one
`shared_memory`; the latter's request/response signals are internal. The
top-level parameter `MEMORY_LINE_COUNT` defaults to 256 and passes to
`shared_memory.LINE_COUNT`. `MEMORY_RESPONSE_LATENCY` defaults to 2 and passes
to `shared_memory.RESPONSE_LATENCY`.

The cache must follow these rules:

1. Use `MC_BUS_RD` for a line read, `MC_BUS_RDX` for exclusive ownership, and
   `MC_BUS_WRITEBACK` for an explicit dirty-line write-back.
2. Drive an aligned 32-bit byte address with low bits `[3:0]` equal to zero.
3. Drive the complete 128-bit line on the selected endpoint's
   `cache0_req_wdata` or `cache1_req_wdata` for write-back.
4. Hold request type, line address, and write-back data stable while
   request-valid signal is asserted and its matching request-ready signal is
   low.
5. Treat matching request valid and ready asserted together as acceptance.
   Request withdrawal after capture does not cancel or transfer ownership.
6. Permit at most one outstanding request per cache.
7. Consume the selected endpoint's final response only when its
   `cache0_rsp_valid` or `cache1_rsp_valid` is asserted. Responses are routed
   only to the captured owner.
8. On a successful line fill, use the selected endpoint's complete
   `cache0_rsp_data` or `cache1_rsp_data`. Its matching `rsp_shared` signal is
   the captured peer line-present indication, and its matching `rsp_error`
   signal reports transaction failure.
9. A snoop is directed only to the nonowner. While
   endpoint's `snoop_valid` is asserted, consume its exact `snoop_txn`,
   `snoop_line_addr`, and `snoop_requester_id` ports, perform the required MESI
   action, and acknowledge it with the matching `cache0_snoop_rsp_valid` or
   `cache1_snoop_rsp_valid`.
10. Report whether the line exists through the matching
    `cache0_snoop_rsp_present` or `cache1_snoop_rsp_present` port. Report a
    modified copy through the matching `snoop_rsp_dirty` port; the full dirty
    line is exposed through the corresponding exact `snoop_rsp_data_valid` and
    `snoop_rsp_data` ports listed above.

The current `shared_bus` does not consume dirty peer data. A dirty response
suppresses the memory request and returns an owner-only error with zero data.
Therefore dirty-line intervention/write-back sequencing is still unresolved
production functionality owned by Arad and the final integration effort. It
must not be hidden by returning stale memory data.

## Shahab connection guide

### Current decode and completion locations

`cpu_core` extracts:

- `opcode = InstrIn[31:26]`
- `rs = InstrIn[25:21]`
- `rt = InstrIn[20:16]`
- `rd = InstrIn[15:11]`
- `funct = InstrIn[5:0]`

It passes `opcode` and `funct` to `cpu_control`, whose combinational
`case (opcode)` and nested R-type `case (funct)` implement the current decode.
New instruction decode belongs there unless an agreed encoding requires
additional fields.

The existing architectural write-back path is controlled in `cpu_core` by
`normal_write_reg`, `write_reg`, `normal_write_data`, `write_data`,
`normal_reg_we`, and `reg_we`. Ordinary memory operations are identified by
`memory_instruction = MemRead | MemWrite` and are sequenced by `mem_state`
through `MEM_IDLE`, `MEM_WAIT_ACCEPT`, `MEM_WAIT_RESPONSE`, and
`MEM_ERROR_HALT`. `memory_wait` holds the PC, and
`load_response_success` produces exactly one successful load write-back.

### Required ISA integration behavior

- `cpuid`: add decode and result selection in the control/core write-back
  path. The current `cpu_core` has no core-ID input even though
  `MC_CORE_ID_WIDTH` is one. The exact instruction encoding and production
  core-ID port or parameter are unresolved integration decisions.
- `lr.w`: issue the required memory operation through the extended CPU/cache
  contract. Create a reservation only after successful final completion,
  store the exact 32-bit word address, and set its valid bit.
- `sc.w`: compare the exact word address against a valid reservation, perform
  the store only on a valid match, return the architectural success/failure
  value, and clear the reservation after every attempt.
- Remote invalidation: an invalidating write by the other core must clear a
  reservation when the snooped line address and reserved address have equal
  bits `[31:4]`. No production cache-to-CPU reservation-invalidation signal
  currently exists; its name, direction, and pulse/handshake timing are
  unresolved and must be agreed with Arad.
- Local store behavior: the exact set of local non-SC events that clear a
  reservation remains unresolved and must be documented before implementation.
- `amoadd.w`: acquire exclusive line ownership, return the old word to `rd`,
  commit the updated word once, and prevent another bus transaction from
  interleaving across the architectural read-modify-write sequence.

Atomic requests must extend, not bypass, the current memory stall discipline:
request fields remain stable under backpressure, the CPU remains stalled
through final completion, errors do not retire the instruction, and the PC and
register file update exactly once. In particular, `lr.w`, successful or failed
`sc.w`, and `amoadd.w` must not reuse both `normal_reg_we` and a response pulse
in a way that produces duplicate register write-back.

The enums `mc_mem_op_t` and `mc_resp_status_t` already define logical operation
and result values, but no production ports currently carry them. Whether the
active CPU/cache boundary is extended with these types or uses another
team-reviewed adapter is unresolved. Do not treat the test-only
`mock_core.request_op`, `mock_l1.request_op`, or their response-status ports as
accepted production port names.

### Unresolved atomic serialization

The current bus holds one bus transaction at a time, but it has no explicit
multi-transaction lock or atomic request type. The cache-level protocol that
makes `amoadd.w` indivisible, and any minimal demonstrated infrastructure
change it requires, must be agreed by Arad and Shahab and reviewed by the team.
No instruction encodings are finalized in the active repository.

## Final system assembly guide

The expected final production hierarchy is:

```text
final dual-core top (module name unresolved)
├── CPU/core instance 0
│   └── private real L1 cache instance 0
├── CPU/core instance 1
│   └── private real L1 cache instance 1
└── multicore_interconnect_top
    ├── shared_bus
    │   └── rr_arbiter
    └── shared_memory
```

Arad must create the production L1 module(s), connect each CPU data interface,
and bind the two L1 bus/snoop sides to the exact `cache0_*` and `cache1_*`
ports. Shahab must update the CPU/control path for core ID and atomic
instructions and create the reservation logic. Arad and Shahab jointly must
create the final dual-core top, provide instruction sources for each CPU's
`InstrIn`/`InstrAddr` interface, assign IDs 0 and 1, connect reservation
invalidation, resolve dirty-peer and atomic serialization behavior, and add
full-system tests. The final top module name and production instruction-memory
organization are unresolved decisions.

## Current regression baseline

`scripts/test.sh` currently exposes these exact accepted targets:

- `cpu_baseline`
- `interfaces`
- `cpu_memory_handshake`
- `rr_arbiter`
- `shared_bus`
- `shared_memory`
- `bus_memory`
- `multicore_interconnect_top`
- `all`

Every future cache, atomic, or final-integration pull request must keep all of
them passing. The `all` target currently runs the eight named regressions
above it.

Arad and Shahab must add at least these new self-checking acceptance targets:

- `l1_cache`: CPU handshake, hits, misses, allocation, replacement,
  write-back, byte/word selection, full-line data, errors, backpressure, and
  reset for one production L1.
- `mesi_coherence`: two real caches covering all required MESI transitions,
  `BusRd`, `BusRdX`, sharing, invalidation, clean and dirty ownership transfer,
  write-back, simultaneous requests, and data consistency.
- `atomic_reservation`: `cpuid`, `lr.w`, successful and failed `sc.w`, clearing
  after every SC, remote and agreed local invalidation, `amoadd.w`, delayed
  cache responses, stalls, errors, and exactly one architectural write-back.
- `dual_core_system`: two CPUs and two real caches running shared-memory and
  atomic programs, contention, reset/recovery, error propagation, no duplicate
  completion, and timeout protection.

After those targets are added, `all` must include them.

## Git and handoff workflow

Arad and Shahab must use this workflow:

1. Fetch the latest `develop`.
2. Create a feature branch from `develop`.
3. Implement only the assigned responsibility.
4. Add self-checking regressions for the change.
5. Run every existing regression, including `./scripts/test.sh all`.
6. Push the feature branch.
7. Open a pull request into `develop`.
8. Perform integration only through reviewed pull requests.
9. When the complete system is accepted, merge `develop` into `main`.

No teammate should build new work from the outdated `main` branch.

## Decisions that must be recorded before final integration

Arad and Shahab must resolve and document:

- instruction encodings for `cpuid`, `lr.w`, `sc.w`, and `amoadd.w`;
- the production core-ID port or parameter and its propagation;
- the active CPU/cache operation and response extension for atomics;
- the reservation module location and production ports;
- remote invalidation signal name, direction, timing, and reset behavior;
- the local non-SC reservation-clear policy;
- dirty-peer intervention/write-back sequencing and use of dirty snoop data;
- atomic serialization across cache and bus behavior;
- production L1 module names and any additional internal cache signals;
- final dual-core top name and instruction-memory organization;
- cache capacity/index parameters and performance-counter definitions;
- the detailed division of the remaining joint tasks between Arad and Shahab.

These are unresolved integration decisions, not completed Ehsan
infrastructure.
