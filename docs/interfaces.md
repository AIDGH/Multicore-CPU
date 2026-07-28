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

### Cache-owned request signals

- `bus_request_valid`
- `bus_transaction`: `BusRd`, `BusRdX`, or dirty write-back/flush
- `bus_requester_id`
- `bus_line_address`: 32-bit byte address with bits `[3:0]` equal to zero
- `bus_writeback_data`: 128-bit dirty line for write-back/flush

### Bus-owned requester response signals

- `bus_request_ready` or grant: accepts one cache request
- `bus_transaction_complete`: final completion for the current owner
- `bus_response_data`: returned 128-bit line
- `bus_response_shared`: indicates that another cache reported a copy

### Bus-owned snoop broadcast

- `snoop_valid`
- `snoop_transaction`
- `snoop_requester_id`
- `snoop_line_address`

### Snooping-cache response

- `snoop_response_valid`: the snoop response is complete
- `snoop_present`: the cache holds the line in a valid state
- `snoop_dirty`: the cache owns newer dirty data
- `snoop_data_valid`
- `snoop_data`: 128-bit dirty-data response

### Protocol

1. The bus accepts only one coherence transaction at a time.
2. Arbitration selects one requesting cache as transaction owner.
3. Ownership remains with that cache until snoop handling, any dirty-data
   transfer or write-back, memory activity, and the final requester response
   all complete.
4. The nonowner cache receives the snoop broadcast and must complete its
   response even when it does not hold the requested line.
5. Dirty peer data takes precedence over stale main-memory data.
6. The bus reports whether another cache had a copy so a requesting cache can
   later distinguish exclusive from shared ownership.

These signals describe transport and ownership only. MESI transition policy is
not defined or implemented here.

## Shared bus to main memory

### Bus-owned request signals

- `memory_request_valid`
- `memory_request_op`: line read or line write
- `memory_line_address`: aligned 32-bit byte address
- `memory_write_data`: 128-bit line

### Memory-owned signals

- `memory_request_ready`
- `memory_response_valid`
- `memory_read_data`: 128-bit line

### Protocol

1. Acceptance occurs on `memory_request_valid && memory_request_ready`.
2. Request fields remain stable until acceptance.
3. The bus permits only one outstanding shared-memory transaction.
4. Memory may apply arbitrary acceptance and completion latency.
5. `memory_response_valid` indicates final read or write completion.
6. A write may ignore `memory_read_data`; a read returns the requested line.

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
