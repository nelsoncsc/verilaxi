#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if (($# > 0)); then
    READY_PROBS=("$@")
else
    READY_PROBS=(100 70 50 30)
fi
OBJ_DIR="${OBJ_DIR:-work/obj_vdma_validate}"
VERILATOR_JOBS="${VERILATOR_JOBS:-12}"

echo "VDMA validation profile"
echo "  ready probabilities: ${READY_PROBS[*]}"
echo "  obj dir: ${OBJ_DIR}"
echo

for ready_prob in "${READY_PROBS[@]}"; do
    echo "=== VDMA validation READY_PROB=${ready_prob} ==="
    make_log="work/logs/vdma_validate_rp${ready_prob}.make.log"
    mkdir -p work/logs
    if make clean run \
        OBJ_DIR="${OBJ_DIR}" \
        VERILATOR_JOBS="${VERILATOR_JOBS}" \
        TESTNAME=vdma \
        READY_PROB="${ready_prob}" \
        VDMA_VALIDATE=1 >"${make_log}" 2>&1; then
        grep -E "VDMA THROUGHPUT|VDMA STRESS|VDMA VALIDATION|Simulation complete" \
            "work/logs/vdma_rp${ready_prob}_val1.log"
        echo "  full make log: ${make_log}"
        echo
    else
        echo "VDMA validation failed for READY_PROB=${ready_prob}" >&2
        tail -n 120 "${make_log}" >&2
        exit 1
    fi
done

echo "VDMA validation summary"
for ready_prob in "${READY_PROBS[@]}"; do
    log_file="work/logs/vdma_rp${ready_prob}_val1.log"
    if [[ -f "${log_file}" ]]; then
        grep -E "VDMA THROUGHPUT|VDMA STRESS|VDMA VALIDATION|Simulation complete" "${log_file}"
    else
        echo "missing log: ${log_file}" >&2
        exit 1
    fi
done
