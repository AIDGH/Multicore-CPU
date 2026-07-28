# Shared Interface Contracts

This document defines the responsibility-level contracts used by the active
multicore implementation. It does not define instruction encodings, MESI
transitions, or implementation-specific state machines.

## Fixed system conventions

- Active-system addresses are 32-bit byte addresses.
- A word is 32 bits.
- A cache line is 16 bytes / 128 bits.
- A line identity is `address[31:4]`.
- A full aligned line address is `{address[31:4], 4'b0000}`.
- Core IDs are one bit for the two-core system.
- Each core may have at most one outstanding data request.
- The shared bus and shared memory each allow only one active transaction.
- Request acceptance and operation completion are separate events.

## Core to L1 cache

### Active CPU data-side signals

- `data_req_valid`: indicates a pending memory operation.
- `data_req_ready`: accepts the request when high in the same cycle as
  `data_req_valid`.
- `data_req_addr`: 32-bit byte address.
- `data_req_write`: `0` for an ordinary word load and `1` for an ordinary
  word store.
- `data_req_wdata`: store data; ignored for loads.
- `data_rsp_valid`: asserted only after the accepted operation completes.
- `data_rsp_rdata`: returned load data.
- `data_rsp_error`: indicates that the completed operation failed.

### Protocol

1. A request is accepted on `data_req_valid && data_req_ready`.
2. The core must keep address, operation, and write operand stable while
   `data_req_valid` is high and `data_req_ready` is low.
3. After acceptance, the core deasserts `data_req_valid`, but it may not
   issue another data request until the response arrives.
4. The core waits from request issue through `data_rsp_valid`; its PC and
   affected architectural state must not retire the operation early.
5. `data_rsp_valid` represents completion, not merely queueing or bus
   acceptance.
6. A successful load writes its destination register exactly once when the
   response arrives. A store completes only when its response arrives and
   never writes a register.
7. An error response suppresses completion, leaves the PC and architectural
   state unchanged, and places the CPU in a terminal memory-error stall until
   reset. The current foundation has no data-access exception, retry, or trap
   mechanism.

The active CPU currently supports only ordinary word loads and stores through
this interface. Cache-coherence operations, atomics, reservations, and
multicore extensions remain deferred.

## L1 cache to shared bus

The bus has two explicit requester endpoints. Bit 0 identifies requester/core 0
and bit 1 identifies requester/core 1.

### Cache-owned request signals

- `l1_req_valid[1:0]`
- `l1_req_txn_0`, `l1_req_txn_1`: `MC_BUS_RD`, `MC_BUS_RDX`, or
  `MC_BUS_WRITEBACK`
- `l1_req_line_addr_0`, `l1_req_line_addr_1`: aligned 32-bit byte addresses
- `l1_req_wdata_0`, `l1_req_wdata_1`: 128-bit write-back lines

### Bus-owned request and response signals

- `l1_req_ready[1:0]`: one-hot acceptance indication for the selected request
- `l1_rsp_valid[1:0]`: one-cycle final response, asserted only for the owner
- `l1_rsp_data_0`, `l1_rsp_data_1`: downstream 128-bit response data
- `l1_rsp_shared[1:0]`: the snooped peer reported that it holds the line
- `l1_rsp_error[1:0]`: downstream error or unsupported dirty-peer response

### Bus-owned snoop signals

- `snoop_valid[1:0]`: asserted only toward the nonowner
- `snoop_txn`
- `snoop_line_addr`
- `snoop_requester_id`

### Snooping-cache response signals

- `snoop_rsp_valid[1:0]`: acknowledgement from the selected nonowner
- `snoop_rsp_present[1:0]`
- `snoop_rsp_dirty[1:0]`
- `snoop_rsp_data_valid[1:0]`
- `snoop_rsp_data_0`, `snoop_rsp_data_1`

### Protocol

1. The existing round-robin arbiter selects one owner. The bus captures that
   request once and retains ownership through final completion.
2. Request withdrawal after capture does not cancel or transfer the
   transaction.
3. The bus issues a snoop only to the nonowner and waits for
   `snoop_rsp_valid` before accessing downstream memory.
4. After a clean-peer acknowledgement, the bus issues one downstream request,
   holds all request fields stable until acceptance, and then waits for the
   downstream completion response.
5. The bus returns one response only to the original owner. The shared bit is
   the captured peer `snoop_rsp_present` value.
6. A dirty-peer report is not yet serviced by cache-to-cache intervention.
   The bus suppresses the downstream request and returns one owner-only error
   response with zero data. This prevents stale memory data from being
   returned silently.
7. `MC_BUS_RDX` snoop acknowledgement represents completion of the peer-side
   invalidation action. The L1 cache remains responsible for all MESI state
   transitions.

## Shared bus to main memory

### Bus-owned request signals

- `memory_req_valid`
- `memory_req_op`: `MC_LINE_READ` or `MC_LINE_WRITE`
- `memory_req_line_addr`: aligned 32-bit byte address
- `memory_req_wdata`: 128-bit line

### Memory-owned signals

- `memory_req_ready`
- `memory_rsp_valid`
- `memory_rsp_rdata`: 128-bit line
- `memory_rsp_error`

### Protocol

1. Acceptance occurs on `memory_req_valid && memory_req_ready`.
2. Request fields remain stable until acceptance.
3. The bus permits only one outstanding shared-memory transaction.
4. Memory may apply arbitrary acceptance and completion latency.
5. `memory_rsp_valid` indicates final read or write completion.
6. `MC_BUS_RD` and `MC_BUS_RDX` produce line reads.
   `MC_BUS_WRITEBACK` produces a line write using the captured requester data.
7. The downstream data and error indication are routed only to the transaction
   owner.

### Active shared-memory endpoint

`shared_memory` implements this interface with a synthesizable array of
128-bit lines. Its parameters are:

- `LINE_COUNT`: number of stored lines; default 256 (4096 bytes)
- `RESPONSE_LATENCY`: cycles from acceptance to completion; default 2 and
  constrained internally to at least one cycle

The byte address is interpreted as `{line_number, 4'b0000}`. Bits `[31:4]`
form a zero-extended 32-bit line number for the bounds comparison, and the
low `$clog2(LINE_COUNT)` line-number bits select storage after validation.

The memory accepts at most one request, deasserts ready while it is pending,
and requires a held request-valid to be withdrawn before it can be accepted
again. Reads return the selected complete line. Writes commit the captured
complete line once at successful completion and return a zero-data completion
response.

An address with nonzero bits `[3:0]` or a line number greater than or equal to
`LINE_COUNT` completes with `memory_rsp_error`, returns zero data, and performs
no write. Reset cancels pending control state and clears response outputs
without committing a pending write. Reset does not erase the storage array;
unwritten contents are unspecified.

The active integration path is `shared_bus` (including `rr_arbiter`) directly
to `shared_memory` through the signals listed above.

## Structural multicore interconnect top-level

`multicore_interconnect_top` is the active structural shell around one
`shared_bus` and one `shared_memory`. The round-robin arbiter remains internal
to `shared_bus`; the shell adds no arbitration, coherence, or memory policy.

The external cache 0 endpoint uses the `cache0_*` signals, and the external
cache 1 endpoint uses the matching `cache1_*` signals. Each endpoint contains:

- request inputs: `req_valid`, `req_txn`, `req_line_addr`, and `req_wdata`
- the `req_ready` acceptance output
- response outputs: `rsp_valid`, `rsp_data`, `rsp_shared`, and `rsp_error`
- snoop outputs: `snoop_valid`, `snoop_txn`, `snoop_line_addr`, and
  `snoop_requester_id`
- snoop-response inputs: `snoop_rsp_valid`, `snoop_rsp_present`,
  `snoop_rsp_dirty`, `snoop_rsp_data_valid`, and `snoop_rsp_data`

The suffixes above follow either the `cache0_` or `cache1_` prefix exactly.
Endpoint 0 connects only to bus requester/snoop position 0, and endpoint 1
connects only to position 1. The complete bus-to-memory request and response
interface is internal to the shell and directly connects the sole
`shared_bus` instance to the sole `shared_memory` instance.

The `MEMORY_LINE_COUNT` and `MEMORY_RESPONSE_LATENCY` top-level parameters
pass through to `shared_memory.LINE_COUNT` and
`shared_memory.RESPONSE_LATENCY`. Their defaults are 256 lines and two cycles,
matching the memory defaults. The active-high `rst` input is passed directly
to both the bus and memory.

Production CPU and private-L1 cache instances remain deferred. The future real
L1 caches, rather than this structural shell, own MESI state and coherence
policy.

## Coherence to reservation logic

Each core owns one reservation record containing:

- the exact reserved 32-bit word address
- a reservation-valid bit

Reservation events are:

- Set after a successful, completed `lr.w`.
- Queried by `sc.w` using exact word-address equality.
- Cleared after every `sc.w` attempt, whether it succeeds or fails.
- Cleared by local policy events selected in the later atomic implementation.
- Cleared by a remote invalidating write when the invalidation line address and
  reserved address have equal bits `[31:4]`.

Reservation and invalidation intentionally use different granularities:

- `sc.w` checks the exact reserved word address.
- Remote writes invalidate reservations at 16-byte cache-line granularity.

The reservation module and its local-clear policy are deferred.

## Atomic-operation ownership

`amoadd.w` will be issued by the CPU as one cache-level atomic request:

1. The CPU supplies the byte address and 32-bit addend.
2. The cache obtains exclusive ownership of the target line.
3. The cache reads and returns the old word.
4. The cache commits the updated word.
5. No other bus transaction may interleave between ownership acquisition and
   completion of the atomic request.

This document fixes responsibility and transaction boundaries only. It does not
implement `amoadd.w`, bus locking, cache updates, or instruction decoding.

## Deferred decisions

- Instruction encodings for `cpuid`, `lr.w`, `sc.w`, and `amoadd.w`
- MESI state transitions and transient states
- Local non-SC events that clear a reservation
- Exact cycle timing and performance-counter definitions
- Production module port names where integration reveals a direct conflict
