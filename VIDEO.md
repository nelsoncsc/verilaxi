# verilaxi — Video IP, Video DMA & Image Harness

The canonical reference for everything video in verilaxi: the pixel-clock video
infrastructure, both Video DMA engines (single-stream triple-buffer and multi-tap
temporal), and the DPI-C / `stb_image` real-image test harness.

All RTL is plain SystemVerilog (no UVM, no vendor primitives) and synthesises
through Yosys. The general AXI/AXI-Lite/AXI-Stream VIP and DMA/CDMA reference
lives in the [Developer Guide](verilaxi_developer_guide.md); **all video material
lives here.**

For a narrative explanation before diving into this reference, see the Sistenix
posts [Video basics for hardware engineers](https://sistenix.com/video_basics.html)
and [Video DMA: triple-buffering, genlock and temporal taps](https://sistenix.com/vdma.html).
The posts explain the design motivation and theory; this document is the
implementation reference for the RTL, tests, registers, and validation commands.

## Contents
1. [Pipeline at a glance](#1-pipeline-at-a-glance)
2. [Video timing package](#2-video-timing-package)
3. [Video infrastructure modules](#3-video-infrastructure-modules)
4. [Single-stream VDMA](#4-single-stream-vdma)
5. [VDMA register map](#5-vdma-register-map)
6. [Multi-tap temporal VDMA](#6-multi-tap-temporal-vdma)
7. [PNG frame harness (DPI-C / stb_image)](#7-png-frame-harness-dpi-c--stb_image)
8. [Real-image round-trip tests](#8-real-image-round-trip-tests)
9. [Throughput methodology](#9-throughput-methodology)
10. [Test catalog](#10-test-catalog)
11. [Status & hardware gaps](#11-status--hardware-gaps)

---

## 1. Pipeline at a glance

![Video pipeline](docs/video_pipeline.svg)

- **Capture path:** `timing_gen → pattern_gen/PNG → video_to_axis → capture_cdc → VDMA S2MM → memory`
- **Display path:** `memory → VDMA MM2S → display_cdc → axis_to_video → display PHY`
- The two CDC blocks isolate the **pixel clock** (e.g. 74.25 MHz @ 720p) from the
  **AXI clock** (e.g. 200 MHz).
- Inside the AXI domain everything is AXI-Stream — **there is no blanking**; frame
  structure is carried by `tvalid`/`tready`/`tlast`/`tuser(SOF)`. Blanking only
  re-appears at `axis_to_video`, where the timing generator is the master and
  inserts blanking / `BLANK_DATA` when the stream has no pixel.

---

## 2. Video timing package

**File:** `rtl/video/snix_video_pkg.sv`

Defines the `video_timing_t` struct and pre-computed timing presets used by every
video module.

**`video_timing_t` struct**

| Field | Type | Description |
|---|---|---|
| `h_active` | `int unsigned` | Active pixels per line |
| `h_front_porch` | `int unsigned` | Horizontal front porch (pixels) |
| `h_sync_pulse` | `int unsigned` | Horizontal sync pulse width |
| `h_back_porch` | `int unsigned` | Horizontal back porch (pixels) |
| `v_active` | `int unsigned` | Active lines per frame |
| `v_front_porch` | `int unsigned` | Vertical front porch (lines) |
| `v_sync_pulse` | `int unsigned` | Vertical sync pulse width |
| `v_back_porch` | `int unsigned` | Vertical back porch (lines) |

**Timing presets**

| Constant | Resolution | Pixel clock |
|---|---|---|
| `TEST_8x4` | 8×4 | — (protocol simulation only) |
| `TEST_16x8` | 16×8 | — |
| `TEST_32x16` | 32×16 | — |
| `TEST_64x32` | 64×32 | — |
| `TEST_64x48` | 64×48 | — (PNG round-trip frame size) |
| `VGA_640x480` | 640×480 | 25.175 MHz |
| `HD_1280x720` | 1280×720 | 74.25 MHz |
| `FHD_1920x1080` | 1920×1080 | 148.5 MHz |
| `UHD_3840x2160` | 3840×2160 | 594.0 MHz |

The nominal pixel-clock constants (`VGA_640x480_CLK_HZ` etc.) are
`longint unsigned` localparams consumed by simulation clock generators and
synthesis constraints; physical hardware must generate these with a PLL or MMCM.

---

## 3. Video infrastructure modules

### `snix_video_timing_gen` — Video Timing Generator
**File:** `rtl/video/snix_video_timing_gen.sv`

Generates horizontal/vertical sync, active-video window, start-of-frame (SOF),
and end-of-line (EOL) from a `video_timing_t` preset.

| Parameter | Default | Description |
|---|---|---|
| `TIMING` | `VGA_640x480` | Timing preset (`video_timing_t`) |

| Output | Description |
|---|---|
| `hsync` | Horizontal sync pulse (active high, during h_sync_pulse region) |
| `vsync` | Vertical sync pulse (active high, during v_sync_pulse region) |
| `active_video` | High for every pixel within the active area |
| `sof` | Single-cycle pulse at pixel (0,0) of each frame |
| `eol` | Single-cycle pulse at the last active pixel of each line |
| `pixel_x` / `pixel_y` | Horizontal / vertical counters (full H_TOTAL / V_TOTAL range) |

Counters reset on `rst_n`. `pixel_x` wraps at `H_TOTAL−1`; `pixel_y` increments at
each line wrap and resets at `V_TOTAL−1`.

### `snix_video_pattern_gen` — Colour Bar Pattern Generator
**File:** `rtl/video/snix_video_pattern_gen.sv`

Combinational eight-bar colour generator; maps pixel position to 24-bit RGB. Bar
index is `(pixel_x × 8) / h_active`, EBU order white→yellow→cyan→green→magenta→
red→blue→black. Outside the active area `pixel_data = 24'h000000`.

| Bar | Colour | Value | | Bar | Colour | Value |
|---|---|---|---|---|---|---|
| 0 | White | `0xFFFFFF` | | 4 | Magenta | `0xFF00FF` |
| 1 | Yellow | `0xFFFF00` | | 5 | Red | `0xFF0000` |
| 2 | Cyan | `0x00FFFF` | | 6 | Blue | `0x0000FF` |
| 3 | Green | `0x00FF00` | | 7 | Black | `0x000000` |

### `snix_video_to_axis` — Video → AXI-Stream Adapter
**File:** `rtl/video/snix_video_to_axis.sv`

Combinational (no pipeline registers) conversion of native parallel video to
AXI4-Stream.

| Parameter | Default | Description |
|---|---|---|
| `DATA_WIDTH` | 24 | Pixel / stream data width |
| `USER_WIDTH` | 1 | `tuser` width; `tuser[0]` = SOF |

| Video port | AXI-Stream port | Notes |
|---|---|---|
| `video_de` | `m_axis_tvalid` | Active-video enable drives valid |
| `video_sof` | `m_axis_tuser[0]` | Start-of-frame sideband |
| `video_eol` | `m_axis_tlast` | End-of-line marks packet boundary |
| `video_data` | `m_axis_tdata` | Raw pixel data, no re-ordering |

**`overflow` flag** — native video cannot be back-pressured. If `m_axis_tready`
is low while `video_de` is high, the sticky `overflow` flag sets. Production
designs insert `snix_video_capture_cdc` (or at least an async FIFO) immediately
downstream to absorb back-pressure.

### `snix_axis_to_video` — AXI-Stream → Video Adapter
**File:** `rtl/video/snix_axis_to_video.sv`

Converts AXI-Stream back to native video, synchronised to an externally generated
display timing reference. The **timing generator is the master**:
`s_axis_tready = timing_de` — the stream is consumed exactly when the display
window is active. `video_data` outputs `BLANK_DATA` during blanking or stream stall.

| Parameter | Default | Description |
|---|---|---|
| `DATA_WIDTH` | 24 | Pixel / stream data width |
| `USER_WIDTH` | 1 | `tuser` width; `tuser[0]` = SOF |
| `BLANK_DATA` | `'0` | Pixel value driven during blanking |

| Flag | Condition |
|---|---|
| `underflow` | `timing_de` asserted but `s_axis_tvalid` low — display demanded a pixel the stream had not supplied |
| `frame_error` | Accepted pixel has `tuser[0] ≠ timing_sof` or `tlast ≠ timing_eol` — SOF/EOL framing mismatch |

### `snix_video_rgb24_pack` / `_unpack` — RGB24 Repacker
**Files:** `rtl/video/snix_video_rgb24_pack.sv`, `..._unpack.sv`

Pack a 24-bpp AXI-Stream into a wider AXI beat and back. Wraps
`snix_axis_rr_converter` (24↔64: GCD 8 → IN_RATIO 8, OUT_RATIO 3, three 24-bit
pixels per 8-byte beat) with lossless byte mapping and accurate TKEEP on the final
(possibly partial) beat. SOF (`tuser[0]`) uses a `sof_pending` latch so it is
forwarded on the first output beat of a buffered batch.

| Parameter | Module | Default |
|---|---|---|
| `OUT_DATA_WIDTH` | pack | 64 |
| `IN_DATA_WIDTH` | unpack | 64 |

### `snix_video_rgb32_pack` / `_unpack` — RGB32 (XRGB8888)
**Files:** `rtl/video/snix_video_rgb32_pack.sv`, `..._unpack.sv`

Map a 24-bit RGB stream to/from a memory-aligned 32-bit-per-pixel layout
(`{8'h00, R, G, B}` in the low lane) — the natural framebuffer format for a CPU or
display controller. One pixel per 32-bit lane; packer asserts `tkeep[3:0]=4'hf`,
unpacker drops a lane whose low `tkeep` nibble is zero. Single-pixel-per-beat
registered stages with skid-free `s_axis_tready = !m_axis_tvalid || m_axis_tready`.

### `snix_video_rgb_to_ycbcr` / `snix_video_ycbcr_to_rgb` — Colour-Space Converters
**Files:** `rtl/video/snix_video_rgb_to_ycbcr.sv`, `..._ycbcr_to_rgb.sv`

Two-stage pipelined ITU-R BT.601 conversion on a 24-bpp stream. Stage 0 forms the
fixed-point dot products; stage 1 rounds (`+128`), shifts (`>>>8`), offsets, and
clamps. SOF/`tlast` propagate through both stages.

**RGB → YCbCr** (studio range `Y∈[16,235]`, `Cb/Cr∈[16,240]`):
```
Y  = ( 66·R + 129·G +  25·B + 128) >> 8 +  16
Cb = (−38·R −  74·G + 112·B + 128) >> 8 + 128
Cr = (112·R −  94·G −  18·B + 128) >> 8 + 128
```
**YCbCr → RGB** (full-range, clamped `[0,255]`; `C=Y−16, D=Cb−128, E=Cr−128`):
```
R = (298·C            + 409·E + 128) >> 8
G = (298·C − 100·D − 208·E + 128) >> 8
B = (298·C + 516·D            + 128) >> 8
```
The pair is symmetric only within rounding/clamping tolerance (studio↔full-range
round-trip is lossy by construction); `video_csc_rgb_ycbcr` bounds the per-channel
round-trip error.

### `snix_video_csc_422` / `_csc_422_expand` — 4:4:4 ↔ 4:2:2 Chroma Subsampler
**Files:** `rtl/video/snix_video_csc_422.sv`, `..._csc_422_expand.sv`

Convert between 4:4:4 (24-bit, full YCbCr per pixel) and 4:2:2 (32-bit, two luma
sharing one averaged chroma pair).

- **`csc_422`** consumes two 4:4:4 pixels → one 32-bit 4:2:2 beat; chroma is
  box-averaged `(Cb₀+Cb₁+1)>>1`. `YUYV_MODE=1` packs `{Cr,Y₁,Cb,Y₀}`; `=0` (UYVY)
  packs `{Y₁,Cr,Y₀,Cb}`. An odd final pixel is emitted as a single beat.
- **`csc_422_expand`** is the inverse: one 32-bit beat → two 24-bit pixels via an
  `IDLE`/`SECOND` replay; `s_axis_tready` gated to `IDLE` so the upstream stalls
  while the second pixel drains.

| Parameter | Default | Description |
|---|---|---|
| `YUYV_MODE` | `1` | `1` = YUYV byte order, `0` = UYVY |

### `snix_video_capture_cdc` — Capture Clock-Domain Crossing
**File:** `rtl/video/snix_video_capture_cdc.sv`

Bridges the full capture pipeline from pixel clock to AXI clock in one module.

| Parameter | Default | Description |
|---|---|---|
| `DATA_WIDTH` | 64 | AXI-side data width; also sets pack output width |
| `FIFO_DEPTH` | 64 | Async FIFO depth (power of 2) |

```
[capture_clk] rgb24_pack (24→DATA_WIDTH) → snix_axis_afifo (CDC) → [axi_clk] {tuser,tkeep,tdata}
```
The async FIFO carries `DATA_WIDTH + KEEP_WIDTH + 1` bits (tdata+tkeep+tuser as one
word); `tlast` uses the FIFO's native TLAST port.

### `snix_video_display_cdc` — Display Clock-Domain Crossing
**File:** `rtl/video/snix_video_display_cdc.sv`

Symmetric inverse: AXI clock → display pixel clock.

| Parameter | Default | Description |
|---|---|---|
| `DATA_WIDTH` | 64 | AXI-side input data width |
| `FIFO_DEPTH` | 64 | Async FIFO depth |

```
[axi_clk] snix_axis_afifo (CDC) → [display_clk] rgb24_unpack (DATA_WIDTH→24) → m_axis_* (24-bit)
```

---

## 4. Single-stream VDMA

Full-frame scatter-gather pipeline for progressive video: an S2MM engine writes
one frame at a time into an AXI4 memory triple-buffer, a frame store manages
rotation and newest-frame tracking, and an MM2S engine reads frames back to an
AXI-Stream display pipeline. Software controls everything through a 16-register
AXI-Lite CSR bank.

![snix_axi_vdma testbench architecture](docs/snix_axi_vdma.svg)

*Testbench architecture of `snix_axi_vdma`.* The capture lane (top) runs
`AXIS_SOURCE` (pattern_gen / PNG frame) → `SNIX_AXIS_FIFO` → **S2MM FSM** →
`s2mm_axi4_if` into the shared `AXI_SLAVE(RAM)` triple-buffer. The playback lane
(bottom) runs `AXI_SLAVE(RAM)` → `mm2s_axi4_if` → **MM2S FSM** → `SNIX_AXIS_FIFO`
→ `AXIS_SINK` (pixel checker / PNG sink). `AXIL_MASTER` drives the
`SNIX_AXI_VDMA_CSR` over `axil_if`. The blue `SNIX_AXI_VDMA_FRAME_STORE` holds
the three buffer slots: the S2MM engine publishes via `write_slot`, the MM2S
engine selects via `read_slot`, and the CSR programs genlock / frame_delay / park
through `FRAME_CTRL`. Both FSMs are drawn as a `state → next_state` register so
the engine structure mirrors the RTL.

### `snix_axi_vdma` — Top-Level
**File:** `rtl/axi/snix_axi_vdma.sv`

Integration wrapper connecting CSR, frame store, S2MM, and MM2S. Separate AXI4
master ports for S2MM writes (`s2mm_*`) and MM2S reads (`mm2s_*`) so the engines
can map to independent memory ports.

| Parameter | Default | Description |
|---|---|---|
| `ADDR_WIDTH` | 32 | AXI4 memory address width |
| `DATA_WIDTH` | 32 | AXI4 memory and stream data width |
| `AXIL_ADDR_WIDTH` / `AXIL_DATA_WIDTH` | 32 / 32 | AXI-Lite CSR widths |
| `ID_WIDTH` | 4 | AXI4 ID width |
| `USER_WIDTH` | 1 | USER sideband width |
| `LINE_FIFO_DEPTH` | 64 | Line FIFO depth per engine |

Top-level status outputs: `wr_busy/wr_done/wr_error/wr_axi_error`,
`rd_busy/rd_done/rd_error/rd_axi_error`, `irq`, `vdma_status[31:0]`,
`write_slot[1:0]`, `read_slot[1:0]`, `newest_complete_slot[1:0]`, `valid_slots[2:0]`.

### `snix_axi_vdma_frame_store` — Triple-Buffer Frame Store
**File:** `rtl/axi/snix_axi_vdma_frame_store.sv`

Rotates the write side 0→1→2→0, avoiding the slot the reader is consuming.
Playback selection priority:
1. **Park mode** — if `park_mode` and `park_slot` valid, always read `park_slot`.
2. **Frame delay** — `delayed_candidate = newest_complete_slot − frame_delay` (mod 3); read it if valid.
3. **Newest** — fall back to `newest_complete_slot`.

`frame_delay=0` = latest frame (zero-delay genlock); `=1` one-frame lag (lets the
downstream drain before overwrite); `=2` two-frame lag. `overwrite_event` fires
when the writer's next slot still holds an unread valid frame.

### `snix_axi_vdma_s2mm` — Stream-to-Memory Engine
**File:** `rtl/axi/snix_axi_vdma_s2mm.sv`

Captures one frame from AXI-Stream into memory; per-line bursts of up to
`burst_len+1` beats with 4 KB-boundary clipping; stride allows inter-line padding.

| State | Description |
|---|---|
| `IDLE` | Waiting for `frame_start` |
| `ACTIVE` | Issuing AW/W; advances line counter after each BRESP |
| `ABORT` | Drains outstanding B responses after stop/error |

Up to `MAX_OUTSTANDING=4` AW descriptors in flight; a descriptor FIFO matches each
BRESP to its byte count. Sticky error flags (cleared on next `frame_start`):
`marker_error` (unexpected `tlast` position), `config_error` (zero hsize/vsize),
`abort_error` (`frame_stop` mid-frame), `axi_error` (non-OKAY BRESP).

### `snix_axi_vdma_mm2s` — Memory-to-Stream Engine
**File:** `rtl/axi/snix_axi_vdma_mm2s.sv`

Reads one frame from memory to AXI-Stream; mirrors S2MM (per-line AR bursts, 4 KB
clipping, outstanding-request limit).

| State | Description |
|---|---|
| `IDLE` | Waiting for `frame_start` |
| `ACTIVE` | Issuing AR; R data → line FIFO → `m_axis_*` |
| `WAIT_OUTPUT` | All AR issued; draining FIFO before `frame_done` |
| `ABORT` | Draining after error / stop |

`TLAST` on the last beat of each line; `TUSER[0]` = SOF on the first beat of the
first line. Up to `MAX_OUTSTANDING=4` AR bursts prefetched ahead of the drain
position to hide read latency.

**Measured (64×32 frame, 64-bit bus, burst-len=15):** MM2S ~**88%** bus efficiency
across `READY_PROB`; S2MM ~**86%** with no memory back-pressure. Main remaining
optimisation is per-line/burst turnaround idle on the write path.

---

## 5. VDMA register map

`snix_axi_vdma` — base address application-defined, all registers 32-bit,
4-byte-aligned, `AXIL_DATA_WIDTH=32`.

| Offset | Name | Access | Description |
|---|---|---|---|
| `0x00` | `WR_CTRL` | R/W | S2MM control — start/stop/circular/size/len |
| `0x04` | `WR_ADDR` | R/W | S2MM base address (single-frame mode) |
| `0x08` | `WR_STRIDE` | R/W | S2MM line stride (bytes) |
| `0x0C` | `RD_CTRL` | R/W | MM2S control |
| `0x10` | `RD_ADDR` | R/W | MM2S base address (single-frame mode) |
| `0x14` | `RD_STRIDE` | R/W | MM2S line stride (bytes) |
| `0x18` | `STATUS` | RO | Live status (hardware-written) |
| `0x1C` / `0x20` | `WR_HSIZE` / `WR_VSIZE` | R/W | S2MM geometry (bytes/line, lines) |
| `0x24` / `0x28` | `RD_HSIZE` / `RD_VSIZE` | R/W | MM2S geometry |
| `0x2C`…`0x34` | `FRAME_ADDR0..2` | R/W | Triple-buffer slot base addresses |
| `0x38` | `FRAME_CTRL` | R/W | Frame-store mode, genlock, IRQ enables, clear |
| `0x3C` | `IRQ_ACK` | W1S | Interrupt/fault acknowledge (self-clearing) |

**`0x00 WR_CTRL`** — `[0]` wr_start (W1S), `[1]` wr_stop (W1S), `[2]` wr_circular,
`[5:3]` wr_beat_size (awsize; 3 = 8 B/beat), `[13:6]` wr_burst_len (awlen).
`RD_CTRL` is identical for MM2S.

**`0x18 STATUS` (read-only)** — `[0]` wr_done, `[1]` rd_done, `[2]` wr_busy,
`[3]` rd_busy, `[4]` wr_error, `[5]` rd_error, `[6]` wr_axi_error, `[7]` rd_axi_error,
`[8]` irq, `[10:9]` write_slot, `[12:11]` read_slot, `[14:13]` newest_complete_slot,
`[17:15]` valid_slots, `[18]` genlock_pending, `[19]` rd_frame_available,
`[23:20]` underrun_count, `[27:24]` overwrite_count, `[31:28]` sync_loss_count.

**`0x38 FRAME_CTRL`** — `[0]` frame_store_enable, `[1]` park_mode, `[3:2]` park_slot,
`[4]` genlock_enable, `[6:5]` frame_delay (0/1/2), `[8]` irq_on_wr_done,
`[9]` irq_on_rd_done, `[10]` irq_on_error, `[16]` global_clear (W1S — clears IRQ
latch, sticky faults, and telemetry counters together).

**`0x3C IRQ_ACK`** — `[0]` irq_ack, `[1]` fault_ack, `[2]` telemetry_ack (all W1S).

**Typical init (frame-store + genlock):**
```c
write_reg(FRAME_ADDR0, 0x1000_0000);
write_reg(FRAME_ADDR1, 0x1010_0000);
write_reg(FRAME_ADDR2, 0x1020_0000);
write_reg(WR_HSIZE, 1920*8); write_reg(WR_VSIZE, 1080); write_reg(WR_STRIDE, 1920*8);
write_reg(RD_HSIZE, 1920*8); write_reg(RD_VSIZE, 1080); write_reg(RD_STRIDE, 1920*8);
write_reg(FRAME_CTRL, (1<<0)|(1<<4)|(0<<5)|(1<<8));   // store + genlock + delay0 + irq_wr
write_reg(WR_CTRL, (15<<6)|(3<<3)|(1<<2)|1);          // burst16, 8B beat, circular, start
write_reg(RD_CTRL, (15<<6)|(3<<3)|1);                 // start MM2S
while (!(read_reg(STATUS) & 0x1));                    // wait wr_done
write_reg(IRQ_ACK, 0x1);
```

---

## 6. Multi-tap temporal VDMA

**File:** `rtl/axi/snix_axi_multi_vdma.sv` (+ `..._multi_vdma_frame_store.sv`)

One S2MM capture path (identical to `snix_axi_vdma`) feeds an **(NUM_TAPS+1)-slot**
frame store; **NUM_TAPS independent MM2S read ports** each expose a *different
generation* of the same video, time-aligned:

```
   tap 0   = newest complete frame   (current)
   tap 1   = previous frame          (current − 1)
   tap N-1 = oldest retained frame   (current − (N-1))
```

Each tap has its own AXI4 read master and AXI-Stream output, so a downstream
filter (temporal denoise, motion detection, frame differencing) reads several
frames in parallel. All array ports are **flat-packed** for Yosys — element `i`
at `[i*W +: W]`.

![snix_axi_multi_vdma testbench architecture](docs/snix_axi_multi_vdma.svg)

*Testbench architecture of `snix_axi_multi_vdma` (drawn for `N=2 TAPS`).* The
capture lane is unchanged from the single VDMA — one `AXIS_SOURCE` →
`SNIX_AXIS_FIFO` → **S2MM FSM** → `s2mm_axi4_if` → shared `AXI_SLAVE(RAM)`. The
difference is on the read side: the `SNIX_AXI_VDMA_FRAME_STORE` (still three
slots) feeds **N independent MM2S taps**, each with its own
`mm2s_axi4_if[i]` / `m_axis_if[i]` / `axis_if[i]` and its own `AXIS_SINK[i]`
(pixel checker / PNG sink). An **AXI CROSSBAR** arbitrates the N read masters onto
the single memory port. `read_slot` from the frame store now resolves *per tap* —
tap 0 gets the newest frame, tap 1 the previous, and so on — which is what lets
the inter-tap frame-diff (§8) visualise motion. `AXIL_MASTER` → `SNIX_AXI_VDMA_CSR`
and the `write_slot` / `FRAME_CTRL` paths are identical to the single VDMA.

| Parameter | Default | Notes |
|---|---|---|
| `NUM_TAPS` | 2 | 1, 2, or 3 (frame store has `NUM_TAPS+1` slots) |
| `DATA_WIDTH` | 32 | AXI / stream data width |
| `LINE_FIFO_DEPTH` | 64 | per-engine line FIFO |

**CSR map (AXI-Lite, 32-bit):**

| Addr | Reg | Notes |
|---|---|---|
| 0x00 | `WR_CTRL` | S2MM control |
| 0x08 | `WR_STRIDE` | bytes/line |
| 0x0c | `RD_CTRL` | applied to **all** MM2S taps |
| 0x14 | `RD_STRIDE` | |
| 0x18 | `STATUS` | RO; `[9]=rd_taps_available`, `[8]=irq`, `[10+i]=rd_busy[i]`, `[27:24]=overwrite_count` |
| 0x1c / 0x20 | `WR_HSIZE` / `WR_VSIZE` | capture geometry (bytes, lines) |
| 0x24 / 0x28 | `RD_HSIZE` / `RD_VSIZE` | playback geometry |
| 0x2c…0x38 | `FRAME_ADDR0..3` | slot base addresses (ADDR2 needs NUM_TAPS≥2, ADDR3 needs NUM_TAPS=3) |
| 0x3c | `FRAME_CTRL` | `[0]` frame_store_enable, `[8]` wr_irq_en, `[9]` rd_irq_en, `[10]` err_irq_en, `[16]` sw_clear |
| 0x40 | `IRQ_ACK` | `[0]` irq_ack, `[1]` fault_clear, `[2]` telemetry_clear |

**Operational notes** (each cost a debugging cycle — encoded as test invariants):
- The DUT is elaborated with the compile-time `NUM_TAPS`. `RD_CTRL` start fires
  **every** hardware tap; if you only consume some, you **must still drain** the
  rest — an undriven `tready=0` leaves that tap's `tap_rd_lock` asserted forever
  and stalls the writer (no spare slot to absorb it).
- The frame store flushes its age queue / valid slots **only when
  `frame_store_enable` goes LOW** — a `sw_clear` pulse alone does *not* reset it.
- Warm `NUM_TAPS+1` frames before reading so `rd_taps_available` (`STATUS[9]`)
  asserts and every slot is valid.
- The multi-VDMA TB uses **separate write/read memory models**, so captured data
  must be mirrored from the S2MM slave into each MM2S slave before a tap can read
  it (`stress_mirror_region`).

---

## 7. PNG frame harness (DPI-C / stb_image)

**Files:** `tb/classes/video/video_frame_source.sv`, `..._sink.sv`,
`tb_cpp/video_frame_dpi.cpp`, vendored `tb_cpp/stb_image.h` / `stb_image_write.h`.

A DPI-C harness that moves **real images** in and out of the pipeline so a test can
drive a known picture and byte-compare the captured/played-back result. It sits
**alongside** `snix_video_pattern_gen` (the default stimulus), not as a
replacement. No external dependencies — `stb_image` is vendored.

### DPI-C entry points (`video_frame_dpi.cpp`, linked into every build)

| Function | Side | Purpose |
|---|---|---|
| `vf_src_load(path)` | source | Load PNG into the C buffer (`stbi_load`, forced 3-channel) |
| `vf_src_load_append(path)` | source | Append another frame (multi-frame sequences) |
| `vf_src_get_pixel(idx)` | source | Packed RGB24 for a flat pixel index (R in `[23:16]`; wraps over all loaded frames) |
| `vf_src_total_pixels()` | source | Total pixels loaded — load-failure guard |
| `vf_src_width()` / `vf_src_height()` | source | Loaded image dimensions |
| `vf_sink_push(rgb24)` / `vf_sink_write(path,w,h)` | sink | Single-stream accumulate → PNG (`<prefix>_<N>.png`, N from 1) |
| `vf_sink_push_n(tap,rgb24)` / `vf_sink_write_n(tap,path,w,h)` | sink | **Per-tap** accumulate → PNG (multi-VDMA, up to 3 taps) |
| `vf_diff_write(a,b,path,w,h,amp)` | diff | \|tap a − tap b\| × amp → PNG (motion visual) |
| `vf_diff_count(a,b,w,h)` | diff | Number of differing pixels (programmatic check) |
| `vf_diff_energy_x1000(a,b,w,h)` | diff | Mean abs diff × 1000 |

**SV TB modules** — `video_frame_source` (drives a 24-bit RGB stream from a loaded
PNG, idle/`tvalid` low with no source) and `video_frame_sink` (accumulates a stream
and flushes one PNG per frame). The source repeats the image for multi-frame runs.

**Make variables** (`mk/config.mk`) forward to `+plusargs`: `PNG_SRC`,
`PNG_SRC_DIR`, `PNG_SINK_PREFIX`, `MVDMA_PNG_DIR` (legacy same input/output
directory), `MVDMA_PNG_SRC_DIR`, `MVDMA_PNG_OUT_DIR`; mode define `VIDEO_PNG`.

> **Verilator note.** Under the `--timing` scheduler a submodule monitor sampling
> `posedge` signals can fire *before* a sibling submodule's NBA has propagated
> through combinational logic (e.g. `m_axis_tvalid = (state == DRAIN)`). Verilator
> tests therefore **inline** the sink DPI calls in the test's pixel-checker
> `always_ff` (evaluated in the correct post-NBA context). The `video_frame_sink`
> module is retained for event-driven simulators (VCS/Questa/Xsim).

> **PNG comparison caveat.** `stbi_write_png` applies per-row PNG filters
> (Sub/Up/Average/Paeth). A naive decoder that strips the filter-type byte without
> *un-filtering* reports false mismatches — any comparison script must reverse the
> row filter before diffing pixels.

---

## 8. Real-image round-trip tests

The input frames are version-controlled fixtures in `tb/assets/squirrel/`
(`frame_00.png` … `frame_05.png`, 64×48 RGB24, six consecutive frames of motion).
Generated outputs go to a separate (gitignored) directory under `work/` so
fixtures never get mixed with artifacts.

### Single-stream (`vdma_timing`)
Drives 6 frames through the **real pixel-clock pipeline** (74.25 MHz pixel ≠
200 MHz AXI, CDC both sides) and verifies each output pixel byte-exact:
```bash
make clean run TESTNAME=vdma_timing VIDEO_PNG=1 \
  PNG_SRC_DIR=tb/assets/squirrel \
  PNG_SINK_PREFIX=work/frames/squirrel_out/timing
# → timing_1.png … timing_6.png, all byte-exact
```

### Multi-tap temporal (`multi_vdma`)
Streams the sequence through the N-tap VDMA; per round writes each tap's view plus
inter-tap **frame-diff** images that visualise motion (each tap lags its
predecessor by exactly one captured generation):
```bash
make clean run TESTNAME=multi_vdma MULTI_VDMA_TAPS=3 \
  MVDMA_PNG_SRC_DIR=tb/assets/squirrel \
  MVDMA_PNG_OUT_DIR=work/frames/squirrel_out
# → out_tap{0,1,2}_rN.png  (newest / −1 / −2 generations)
# → diff_t0_t1_rN.png, diff_t1_t2_rN.png  (motion)
```
The directed synthetic checkpoints assert byte-exact temporal ordering. The PNG
phase adds real-image evidence: it verifies the frame stream completes, writes
per-tap images, and asserts adjacent taps differ (`vf_diff_count > 0`, real
motion present). Passes for `MULTI_VDMA_TAPS` ∈ {1,2,3}.

---

## 9. Throughput methodology

The multi-VDMA PNG phase instruments MM2S read throughput per frame and reports two
efficiency windows:

- **steady** = first delivered beat → last beat (in-frame delivery)
- **total** = first `tready` assert → last beat (adds AR-issue / read latency)

```
round 0 tap0: 3072 beats | steady 3835 cyc (80%) | total 3835 cyc (80%) | AR-lat 0
...
steady efficiency 80%  |  steady BW @200MHz: ~1281 MB/s (24576 bytes/frame, 8B/beat)
```

**Interpretation:**
- **No blanking** — this is AXI-Stream, so every non-delivering cycle is *real*
  lost bandwidth, not protocol overhead. 80% steady means the MM2S bubbles ~1 beat
  in 5 at line/burst boundaries (FIFO refill), **not** one big inter-frame gap.
- **AR-lat ≈ 0** is a *simulation artifact*: the behavioral AXI slave has zero read
  latency. On real DDR the per-frame startup gap appears and `total` drops below
  `steady`.

---

## 10. Test catalog

| Test | What it exercises |
|---|---|
| `video_axis_loopback` | timing → pattern → to_axis → axis_to_video → check |
| `video_fifo_loopback` | same path through a sync FIFO |
| `video_afifo_loopback` | same path through async FIFO / CDC |
| `video_adapter_errors` | overflow / underflow / frame_error flags |
| `video_mode_clocks` | pixel-clock period checks (VGA/HD/FHD/UHD) |
| `video_rgb_cdc` | RGB24 pack/unpack across capture/AXI/display clocks |
| `video_rgb32` | XRGB8888 pack/unpack |
| `video_csc_rgb_ycbcr` | BT.601 RGB↔YCbCr round-trip (bounded error) |
| `video_csc_422` | 4:4:4 ↔ 4:2:2 chroma subsample |
| `vdma` | single-stream triple-buffer capture/playback (`READY_PROB`) |
| `vdma_timing` | end-to-end with independent pixel clock + CDC; `VIDEO_PNG=1` for squirrel round-trip |
| `multi_vdma` | multi-tap temporal VDMA; `MVDMA_PNG_SRC_DIR` / `MVDMA_PNG_OUT_DIR` for squirrel round-trip + throughput |

```bash
make run TESTNAME=video_axis_loopback
make run TESTNAME=video_adapter_errors
make run TESTNAME=video_csc_rgb_ycbcr
make run TESTNAME=video_csc_422
make run TESTNAME=vdma READY_PROB=70
make run TESTNAME=multi_vdma MULTI_VDMA_TAPS=3
```

---

## 11. Status & hardware gaps

**Targeted simulation status:** every video IP and both VDMA engines have directed
checkpoint coverage. The squirrel round-trip adds byte-exact real-image validation
for the single-stream timing path plus temporal-tap motion proof and throughput
instrumentation for multi-VDMA.

**Not yet validated on hardware** — gating items for FPGA bring-up (KR260 et al.):
1. **Randomized-latency DDR model** — all numbers are against a fixed-latency
   behavioral slave; `AR-lat = 0` is the tell. Highest-leverage sim improvement.
2. **XDC/SDC constraints** — CDC false-paths + async `clock_groups` on the
   gray-code crossings. Currently absent.
3. **Real pixel clock (MMCM/PLL) + video PHY** (HDMI/DP) — not modelled.
4. **Capture timing *detector*** — the capture path is generator-only; real
   cameras need `de/sof/eol` recovery from raw sync.
5. **Vivado synth + `report_cdc`/`report_timing`** — Yosys passes but is not the
   real gate.

See the [Developer Guide](verilaxi_developer_guide.md) for the general AXI VIP,
DMA/CDMA reference, and simulation/build workflow.
