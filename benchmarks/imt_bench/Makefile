# SPDX-License-Identifier: Apache-2.0
PYTHON ?= python3
RISCV_TOOLS ?= riscv64-unknown-elf
VERILATOR ?= verilator
HOST_CXX ?= g++
JOBS ?= 2
GSF ?= 12
ITERATIONS ?= 12
CLOCK_MHZ ?= 80
IBEX_CONFIG ?= small
WORKLOAD ?= all
BUILD ?= $(CURDIR)/build/$(IBEX_CONFIG)
EMBENCH_DIR ?= $(CURDIR)/.deps/embench
TINY_DIR ?= $(CURDIR)/.deps/tiny
TFLM_DIR ?= $(CURDIR)/.deps/tflm
TIMEOUT ?= 1800
ARGS = --riscv-tools '$(RISCV_TOOLS)' --verilator '$(VERILATOR)' \
 --host-cxx '$(HOST_CXX)' --jobs '$(JOBS)' --gsf '$(GSF)' \
 --iterations '$(ITERATIONS)' --clock-mhz '$(CLOCK_MHZ)' --ibex-config '$(IBEX_CONFIG)' \
 --workload '$(WORKLOAD)' --build-dir '$(BUILD)' --timeout '$(TIMEOUT)' \
 --embench-dir '$(EMBENCH_DIR)' --tiny-dir '$(TINY_DIR)' --tflm-dir '$(TFLM_DIR)'
.PHONY: all prepare build sim run check
all: run
prepare build sim run:
	$(PYTHON) port.py $@ $(ARGS)
check:
	$(PYTHON) verify_port.py --build-dir '$(BUILD)' --riscv-tools '$(RISCV_TOOLS)'
