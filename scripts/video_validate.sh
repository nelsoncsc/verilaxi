#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OBJ_DIR="${OBJ_DIR:-work/obj_video_validate}"
VERILATOR_JOBS="${VERILATOR_JOBS:-12}"

run_case() {
    local label="$1"
    shift

    local log_tag
    log_tag="$(echo "$label" | tr ' /=' '___')"
    local make_log="work/logs/video_validate_${log_tag}.make.log"

    echo "=== VIDEO validation: ${label} ==="
    mkdir -p work/logs
    if make clean run \
        OBJ_DIR="${OBJ_DIR}" \
        VERILATOR_JOBS="${VERILATOR_JOBS}" \
        "$@" >"${make_log}" 2>&1; then
        grep -E "VIDEO|Simulation complete" "$make_log" | tail -n 20
        echo "  full make log: ${make_log}"
        echo
    else
        echo "VIDEO validation failed: ${label}" >&2
        tail -n 120 "${make_log}" >&2
        exit 1
    fi
}

echo "Video validation profile"
echo "  obj dir: ${OBJ_DIR}"
echo

run_case "axis loopback 8x4 timing" \
    TESTNAME=video_axis_loopback
run_case "fifo loopback 8x4 timing" \
    TESTNAME=video_fifo_loopback
run_case "afifo loopback 8x4 timing cdc" \
    TESTNAME=video_afifo_loopback
run_case "adapter errors" \
    TESTNAME=video_adapter_errors
run_case "mode clocks" \
    TESTNAME=video_mode_clocks
run_case "rgb cdc 8x4" \
    TESTNAME=video_rgb_cdc

run_case "axis loopback 64x32 timing" \
    TESTNAME=video_axis_loopback VIDEO_VALIDATE=1
run_case "fifo loopback 32x16 timing" \
    TESTNAME=video_fifo_loopback VIDEO_VALIDATE=1
run_case "afifo loopback 32x16 timing cdc" \
    TESTNAME=video_afifo_loopback VIDEO_VALIDATE=1
run_case "rgb cdc 32x16" \
    TESTNAME=video_rgb_cdc VIDEO_VALIDATE=1

echo "VIDEO VALIDATION COMPLETE"
