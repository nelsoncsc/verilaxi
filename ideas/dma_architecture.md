# AXI DMA Architecture with MM2MM Engine

## Block Diagram

```
                                                    ┌─────────────────────────────┐
                                                    │      AXI Interconnect       │
                                                    │                             │
                                                    │  ┌───────┐    ┌───────┐    │
                                                    │  │  WR   │    │  RD   │    │
                                                    │  │ Slave │    │ Slave │    │
                                                    │  └───┬───┘    └───┬───┘    │
                                                    └──────┼────────────┼────────┘
                                                           │            │
                              ┌─────────────────────────────────────────────────────────────────┐
                              │                        snix_axi_dma                             │
                              │                                                                 │
                              │    ┌─────────────────┐         ┌─────────────────┐             │
                              │    │  WR Arbiter     │         │  RD Arbiter     │             │
                              │    │                 │         │                 │             │
                              │    │ S2MM ──►┐       │         │ MM2S ──►┐       │             │
    AXI-Lite ─────────────────┼───►│         ├──►AXI │         │         ├──►AXI │             │
    (Control)                 │    │ MM2MM──►┘  WR   │         │ MM2MM──►┘  RD   │             │
                              │    │         ◄── B   │         │         ◄── R   │             │
                              │    └────┬───────┬────┘         └────┬───────┬────┘             │
                              │         │       │                   │       │                  │
                              │    ┌────┴───┐ ┌─┴────────────────────┴───┐ ┌┴────────┐         │
                              │    │        │ │                          │ │         │         │
    AXI-Stream ───────────────┼───►│  S2MM  │ │         MM2MM            │ │  MM2S   │────────►│──── AXI-Stream
    (Write Data)              │    │        │ │   (internal datapath)    │ │         │         │     (Read Data)
                              │    │        │ │                          │ │         │         │
                              │    └────────┘ └──────────────────────────┘ └─────────┘         │
                              │                                                                 │
                              └─────────────────────────────────────────────────────────────────┘
```

## ID Allocation

| Engine | AXI ID[0] | Description |
|--------|-----------|-------------|
| S2MM   | 0         | Stream-to-Memory writes |
| MM2MM  | 1         | Memory-to-Memory writes |
| MM2S   | 0         | Memory-to-Stream reads |
| MM2MM  | 1         | Memory-to-Memory reads |

**Note:** ID[3:1] can be used freely by engines for transaction tracking.

## Resource Summary

| Module | LUTs | FFs | BRAM | Description |
|--------|------|-----|------|-------------|
| S2MM   | ~400 | ~250 | 1 | Write engine |
| MM2S   | ~350 | ~200 | 1 | Read engine |
| MM2MM  | ~600 | ~350 | 2 | Copy engine (RD + WR) |
| WR Arbiter | ~150 | ~50 | 0 | S2MM + MM2MM arbitration |
| RD Arbiter | ~100 | ~40 | 0 | MM2S + MM2MM arbitration |
| CSR    | ~200 | ~100 | 0 | Control/Status |
| **Total** | **~1800** | **~990** | **4** | |

## Throughput Analysis

### Single Engine Active

| Configuration | Throughput | Notes |
|---------------|------------|-------|
| S2MM only     | 100% WR BW | Full write bandwidth |
| MM2S only     | 100% RD BW | Full read bandwidth |
| MM2MM only    | 100% RD + 100% WR | Both channels active |

### Multiple Engines Active

| Configuration | S2MM | MM2S | MM2MM | Notes |
|---------------|------|------|-------|-------|
| S2MM + MM2S   | 100% | 100% | - | No contention (different channels) |
| S2MM + MM2MM  | ~50% | - | ~50% | WR channel shared |
| MM2S + MM2MM  | - | ~50% | ~50% | RD channel shared |
| All three     | ~50% | ~50% | ~50% | Both channels shared |

**Effective bandwidth with 64-bit @ 250MHz:**
- Single channel: 16 GB/s
- Shared channel: ~8 GB/s per engine (round-robin)

## Arbitration Details

### Write Arbiter (S2MM + MM2MM)

1. **AW Channel**: Round-robin when both request
2. **W Channel**: Strict ordering - FIFO tracks AW grant order
3. **B Channel**: Route by BID[0]

### Read Arbiter (MM2S + MM2MM)

1. **AR Channel**: Round-robin when both request
2. **R Channel**: Route by RID[0] (can interleave)

### Outstanding Transactions

- Default: 2 per engine
- Configurable via `MAX_OUTSTANDING` parameter
- Higher values improve throughput with high-latency memory

## CSR Map (Proposed)

| Offset | Name | Description |
|--------|------|-------------|
| 0x00 | WR_CTRL | S2MM control (start, stop, circular) |
| 0x04 | WR_BYTE_LEN | S2MM transfer length |
| 0x08 | WR_ADDR | S2MM base address |
| 0x0C | RD_CTRL | MM2S control |
| 0x10 | RD_BYTE_LEN | MM2S transfer length |
| 0x14 | RD_ADDR | MM2S base address |
| 0x18 | STATUS | Done/error flags |
| 0x1C | MM2MM_CTRL | MM2MM control |
| 0x20 | MM2MM_BYTE_LEN | MM2MM transfer length |
| 0x24 | MM2MM_SRC_ADDR | MM2MM source address |
| 0x28 | MM2MM_DST_ADDR | MM2MM destination address |

## MM2MM Engine Design Notes

### Internal Architecture

```
┌─────────────────────────────────────────────────────┐
│                     MM2MM Engine                    │
│                                                     │
│  ┌─────────┐    ┌─────────┐    ┌─────────┐         │
│  │   AR    │───►│  FIFO   │───►│   AW    │         │
│  │  FSM    │    │ (depth  │    │  FSM    │         │
│  │         │    │  = 16)  │    │         │         │
│  └────┬────┘    └─────────┘    └────┬────┘         │
│       │                             │              │
│       │ R channel              W channel           │
│       │                             │              │
│  ┌────┴────┐                   ┌────┴────┐         │
│  │   RD    │───────────────────│   WR    │         │
│  │ Arbiter │                   │ Arbiter │         │
│  └─────────┘                   └─────────┘         │
└─────────────────────────────────────────────────────┘
```

### Key Features

1. **Decoupled Read/Write**: FIFO allows read to run ahead
2. **4K Boundary Handling**: Both RD and WR respect boundaries
3. **Partial Strobe**: Last beat uses correct wstrb
4. **Address Alignment**: Separate source/destination alignment

### FSM States

```
IDLE → RD_PREP1 → RD_PREP2 → AR → READ → [loop or done]
                                    ↓
                              (data to FIFO)
                                    ↓
IDLE ← WR_WAIT ← WR_PREP1 ← WR_PREP2 ← AW ← WRITE
```

## Timing Considerations

All paths optimized for 500MHz:

| Path | Delay | Status |
|------|-------|--------|
| Arbiter grant logic | ~0.8ns | ✅ |
| W owner FIFO lookup | ~0.5ns | ✅ |
| R/B channel demux | ~0.3ns | ✅ |
| ID manipulation | ~0.2ns | ✅ |

## Usage Example

```c
// Start MM2MM copy: 4KB from 0x1000 to 0x2000
write_reg(MM2MM_SRC_ADDR, 0x1000);
write_reg(MM2MM_DST_ADDR, 0x2000);
write_reg(MM2MM_BYTE_LEN, 4096);
write_reg(MM2MM_CTRL, 0x01);  // Start

// Poll for completion
while (!(read_reg(STATUS) & MM2MM_DONE));
```

## Future Enhancements

1. **Scatter-Gather**: Descriptor-based transfers
2. **Interrupt Support**: Completion/error interrupts
3. **QoS Control**: Priority-based arbitration
4. **Statistics**: Transfer counters, latency measurement
