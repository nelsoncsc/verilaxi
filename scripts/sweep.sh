#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

MODE="${1:-all}"
SYNTH_TARGET="${2:-both}"

SIM_TOTAL=0
SIM_PASS=0
SYNTH_TOTAL=0
SYNTH_PASS=0

run_sim_case() {
    local label="$1"
    shift
    SIM_TOTAL=$((SIM_TOTAL + 1))
    echo
    echo "=== SIM: ${label} ==="
    if make clean run "$@"; then
        SIM_PASS=$((SIM_PASS + 1))
    else
        echo "SIM FAILED: ${label}" >&2
        exit 1
    fi
}

run_synth_case() {
    local label="$1"
    shift
    SYNTH_TOTAL=$((SYNTH_TOTAL + 1))
    echo
    echo "=== SYNTH: ${label} ==="
    if make synth "$@"; then
        SYNTH_PASS=$((SYNTH_PASS + 1))
    else
        echo "SYNTH FAILED: ${label}" >&2
        exit 1
    fi
}

run_sim_sweep() {
    local src_bp sink_bp frame_fifo testtype

    for src_bp in 0 1; do
        for sink_bp in 0 1; do
            run_sim_case \
                "axis_register src=${src_bp} sink=${sink_bp}" \
                TESTNAME=axis_register SRC_BP="${src_bp}" SINK_BP="${sink_bp}"
        done
    done

    for frame_fifo in 0 1; do
        for src_bp in 0 1; do
            for sink_bp in 0 1; do
                run_sim_case \
                    "axis_fifo ff=${frame_fifo} src=${src_bp} sink=${sink_bp}" \
                    TESTNAME=axis_fifo FRAME_FIFO="${frame_fifo}" SRC_BP="${src_bp}" SINK_BP="${sink_bp}"
            done
        done
    done

    for frame_fifo in 0 1; do
        for testtype in 0 1 2; do
            for src_bp in 0 1; do
                for sink_bp in 0 1; do
                    run_sim_case \
                        "axis_afifo ff=${frame_fifo} tt=${testtype} src=${src_bp} sink=${sink_bp}" \
                        TESTNAME=axis_afifo FRAME_FIFO="${frame_fifo}" TESTTYPE="${testtype}" SRC_BP="${src_bp}" SINK_BP="${sink_bp}"
                done
            done
        done
    done

    run_sim_case "axil_register" TESTNAME=axil_register

    for testtype in 0 1 2 3 4; do
        run_sim_case \
            "dma tt=${testtype} rp=70" \
            TESTNAME=dma TESTTYPE="${testtype}" READY_PROB=70
    done

    for testtype in 0 1 2 3; do
        run_sim_case \
            "cdma tt=${testtype} rp=70" \
            TESTNAME=cdma TESTTYPE="${testtype}" READY_PROB=70
    done

    echo
    echo "SIM SWEEP COMPLETE: ${SIM_PASS}/${SIM_TOTAL} passed"
}

run_synth_sweep() {
    local targets=()
    local target synth_name

    case "$SYNTH_TARGET" in
        generic)
            targets=(generic)
            ;;
        artix7)
            targets=(artix7)
            ;;
        both)
            targets=(generic artix7)
            ;;
        *)
            echo "Unknown synth target: ${SYNTH_TARGET}" >&2
            echo "Valid values: generic | artix7 | both" >&2
            exit 1
            ;;
    esac

    for target in "${targets[@]}"; do
        for synth_name in axis_register axis_fifo axis_fifo_pkt axis_afifo axis_afifo_pkt axil_register dma cdma; do
            run_synth_case \
                "${synth_name} target=${target}" \
                SYNTH_NAME="${synth_name}" SYNTH_TARGET="${target}"
        done
    done

    echo
    echo "SYNTH SWEEP COMPLETE: ${SYNTH_PASS}/${SYNTH_TOTAL} passed"
}

print_usage() {
    cat <<'EOF'
Usage:
  scripts/sweep.sh [sim|synth|all] [generic|artix7|both]

Examples:
  scripts/sweep.sh sim
  scripts/sweep.sh synth artix7
  scripts/sweep.sh all both
EOF
}

case "$MODE" in
    sim)
        run_sim_sweep
        ;;
    synth)
        run_synth_sweep
        ;;
    all)
        run_sim_sweep
        run_synth_sweep
        ;;
    -h|--help|help)
        print_usage
        ;;
    *)
        echo "Unknown mode: ${MODE}" >&2
        print_usage
        exit 1
        ;;
esac
