#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"

run_cpu_baseline() {
    local test_name="cpu_baseline"
    local build_dir="${repo_root}/build/${test_name}"
    local simulation="${build_dir}/tb_cpu_baseline.vvp"

    mkdir -p "${build_dir}"

    iverilog -g2012 -Wall \
        -s tb_cpu_baseline \
        -o "${simulation}" \
        "${repo_root}/rtl/core/cpu_alu.v" \
        "${repo_root}/rtl/core/cpu_control.v" \
        "${repo_root}/rtl/core/cpu_reg_file.v" \
        "${repo_root}/rtl/core/cpu_multiplier.v" \
        "${repo_root}/rtl/core/cpu_divider.v" \
        "${repo_root}/rtl/core/cpu_mul_div.v" \
        "${repo_root}/rtl/core/cpu_core.v" \
        "${repo_root}/tb/unit/tb_cpu_baseline.sv" \
        2>&1 | tee "${build_dir}/compile.log"

    vvp "${simulation}" 2>&1 | tee "${build_dir}/run.log"
}

run_interfaces() {
    local test_name="interfaces"
    local build_dir="${repo_root}/build/${test_name}"
    local simulation="${build_dir}/tb_interfaces.vvp"

    mkdir -p "${build_dir}"

    iverilog -g2012 -Wall \
        -s tb_interfaces \
        -o "${simulation}" \
        "${repo_root}/rtl/common/mc_defs.svh" \
        "${repo_root}/tb/mocks/mock_core.sv" \
        "${repo_root}/tb/mocks/mock_l1.sv" \
        "${repo_root}/tb/mocks/mock_memory.sv" \
        "${repo_root}/tb/unit/tb_interfaces.sv" \
        2>&1 | tee "${build_dir}/compile.log"

    vvp "${simulation}" 2>&1 | tee "${build_dir}/run.log"
}

run_cpu_memory_handshake() {
    local test_name="cpu_memory_handshake"
    local build_dir="${repo_root}/build/${test_name}"
    local simulation="${build_dir}/tb_cpu_memory_handshake.vvp"

    mkdir -p "${build_dir}"

    iverilog -g2012 -Wall \
        -s tb_cpu_memory_handshake \
        -o "${simulation}" \
        "${repo_root}/rtl/common/mc_defs.svh" \
        "${repo_root}/rtl/core/cpu_alu.v" \
        "${repo_root}/rtl/core/cpu_control.v" \
        "${repo_root}/rtl/core/cpu_reg_file.v" \
        "${repo_root}/rtl/core/cpu_multiplier.v" \
        "${repo_root}/rtl/core/cpu_divider.v" \
        "${repo_root}/rtl/core/cpu_mul_div.v" \
        "${repo_root}/rtl/core/cpu_core.v" \
        "${repo_root}/tb/mocks/mock_l1.sv" \
        "${repo_root}/tb/unit/tb_cpu_memory_handshake.sv" \
        2>&1 | tee "${build_dir}/compile.log"

    vvp "${simulation}" 2>&1 | tee "${build_dir}/run.log"
}

run_rr_arbiter() {
    local test_name="rr_arbiter"
    local build_dir="${repo_root}/build/${test_name}"
    local simulation="${build_dir}/tb_rr_arbiter.vvp"

    mkdir -p "${build_dir}"

    iverilog -g2012 -Wall \
        -s tb_rr_arbiter \
        -o "${simulation}" \
        "${repo_root}/rtl/bus/rr_arbiter.sv" \
        "${repo_root}/tb/unit/tb_rr_arbiter.sv" \
        2>&1 | tee "${build_dir}/compile.log"

    vvp "${simulation}" 2>&1 | tee "${build_dir}/run.log"
}

run_shared_bus() {
    local test_name="shared_bus"
    local build_dir="${repo_root}/build/${test_name}"
    local simulation="${build_dir}/tb_shared_bus.vvp"

    mkdir -p "${build_dir}"

    iverilog -g2012 -Wall \
        -s tb_shared_bus \
        -o "${simulation}" \
        "${repo_root}/rtl/common/mc_defs.svh" \
        "${repo_root}/rtl/bus/rr_arbiter.sv" \
        "${repo_root}/rtl/bus/shared_bus.sv" \
        "${repo_root}/tb/unit/tb_shared_bus.sv" \
        2>&1 | tee "${build_dir}/compile.log"

    vvp "${simulation}" 2>&1 | tee "${build_dir}/run.log"
}

usage() {
    echo "Usage: $0 {cpu_baseline|interfaces|cpu_memory_handshake|rr_arbiter|shared_bus|all}" >&2
}

case "${1:-}" in
    cpu_baseline)
        run_cpu_baseline
        ;;
    interfaces)
        run_interfaces
        ;;
    cpu_memory_handshake)
        run_cpu_memory_handshake
        ;;
    rr_arbiter)
        run_rr_arbiter
        ;;
    shared_bus)
        run_shared_bus
        ;;
    all)
        run_cpu_baseline
        run_interfaces
        run_cpu_memory_handshake
        run_rr_arbiter
        run_shared_bus
        ;;
    *)
        usage
        exit 2
        ;;
esac
