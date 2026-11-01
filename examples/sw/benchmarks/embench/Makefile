###########################################
### Embench one-shot build (wrapper)    ###
###########################################
# Builds the Embench benchmarks for Ibex Simple System with Embench's own
# scons flow, in the same way as the Embench wrapper of the riscv-imt-model
# platform. The board port is in ibex/ (boardsupport.c switches the
# performance counters) and the bare-metal runtime is Simple System's
# (examples/sw/simple_system/common: crt0.S, simple_system_common.c); the
# linker script is ../common/link.ld, shared with the MLPerf Tiny benchmark
# and laid out like the CV32E40P port's (see the note in it).
#
# Build the simulator first, from the repository root, e.g.:
#   fusesoc --cores-root=. run --target=sim --setup --build \
#     lowrisc:ibex:ibex_simple_system $(./util/ibex_config.py small fusesoc_opts)
# Then:
#   make -C examples/sw/benchmarks/embench            # all 19 benchmarks
#   ./examples/sw/benchmarks/embench/run_embench.sh    # run them, logs to runlogs/
# See ../README.md.

# Embench source (git submodule pinned to the revision used by the platform)
EMBENCH_DIR ?= $(CURDIR)/../../../../vendor/embench-iot
PORT_DIR    ?= $(CURDIR)/ibex

# Compiling configuration
RV_ISA ?= rv32im
RV_ABI ?= ilp32
RISCV_TOOLS ?= riscv64-unknown-elf
CC      := $(RISCV_TOOLS)-gcc
AR      := $(RISCV_TOOLS)-ar
OBJDUMP := $(RISCV_TOOLS)-objdump

OPATH     ?= $(CURDIR)/
BUILD_DIR ?= $(OPATH)build-embench
LOG_DIR   ?= $(OPATH)runlogs

# Bare-metal runtime: Simple System's common code, unchanged
SYSTEM_COMMON := $(CURDIR)/../../simple_system/common
CRT           := $(SYSTEM_COMMON)/crt0.S
LINKER_SCRIPT := $(CURDIR)/../common/link.ld

BM_DIR  := $(BUILD_DIR)/baremetal
BM_LIB  := $(BM_DIR)/libbm.a
BM_OBJS := $(BM_DIR)/simple_system_common.o $(BM_DIR)/embench_report.o
# crt0.o is linked as an object, not from the library: nothing references its
# symbols (link.ld computes the entry point), so the archive member would not
# be pulled in.
CRT_OBJ := $(BM_DIR)/crt0.o

# -misa-spec=2.2 lets rv32im imply Zicsr (needed for the CSR instructions)
# with toolchains whose default ISA specification is newer, e.g. xPack; the
# platform's own toolchain is built with --with-isa-spec=2.2 and ignores it.
PORT_CFLAGS = -O3 -march=$(RV_ISA) -mabi=$(RV_ABI) -misa-spec=2.2 -mcmodel=medany -static \
		-std=gnu99 -fno-common -nostartfiles -ffreestanding \
		-mstrict-align -falign-functions=16 -falign-jumps=4

CFLAGS_COMMON   = $(PORT_CFLAGS) -I$(SYSTEM_COMMON) -I$(PORT_DIR) -I$(CURDIR)/../common
# --wrap=main routes Embench's unchanged main() through embench_report.c, which
# prints the counters and the verification result after the run.
LDFLAGS_COMMON := -nostartfiles -static -march=$(RV_ISA) -mabi=$(RV_ABI) -mcmodel=medany \
                  -T $(LINKER_SCRIPT) -Wl,-gc-sections -Wl,--wrap=main \
                  -Wl,-Map=$(OPATH)bench.map -L$(BM_DIR) $(CRT_OBJ)

# Global scale factor (one hart, so the same as the platform's TOTAL_GSF)
GSF ?= 12
WARMUP_HEAT ?= 1

.PHONY: all embench baremetal clean

all: embench

$(BM_DIR):
	mkdir -p $(BM_DIR)

$(BM_DIR)/crt0.o: $(CRT) | $(BM_DIR)
	$(CC) $(CFLAGS_COMMON) -c $< -o $@

$(BM_DIR)/simple_system_common.o: $(SYSTEM_COMMON)/simple_system_common.c | $(BM_DIR)
	$(CC) $(CFLAGS_COMMON) -c $< -o $@

$(BM_DIR)/embench_report.o: $(PORT_DIR)/embench_report.c | $(BM_DIR)
	$(CC) $(CFLAGS_COMMON) -c $< -o $@

$(BM_LIB): $(BM_OBJS)
	$(AR) rcs $@ $^

baremetal: $(BM_LIB) $(CRT_OBJ)

# One-shot build of all Embench benchmarks using scons
embench: baremetal
	mkdir -p $(BUILD_DIR) $(LOG_DIR)
	cd $(EMBENCH_DIR) && scons \
	  --build-dir=$(BUILD_DIR) \
	  --config-dir=$(PORT_DIR) \
	  cc=$(CC) \
	  cflags='$(CFLAGS_COMMON)' \
	  ldflags='$(LDFLAGS_COMMON)' \
	  user_libs='bm m gcc' \
	  gsf=$(GSF) \
	  warmup_heat=$(WARMUP_HEAT)
	$(MAKE) embench-post

clean:
	rm -rf $(BUILD_DIR)
	$(MAKE) embench-clean-post

# ---- Post-processing: collect .elf and .dis into the embench top dir ----
EMBENCH_TOP      := $(CURDIR)
EMBENCH_EXEC_ROOT:= $(BUILD_DIR)/src

.PHONY: embench-post embench-clean-post

embench-post:
	@set -e; \
	for d in "$(EMBENCH_EXEC_ROOT)"/*; do \
	  [ -d "$$d" ] || continue; \
	  b=$$(basename "$$d"); \
	  in="$$d/$$b"; \
	  [ -f "$$in" ] || continue; \
	  cp -f "$$in" "$(EMBENCH_TOP)/$$b.elf"; \
	  "$(OBJDUMP)" -S -D "$$in" > "$(EMBENCH_TOP)/$$b.dis"; \
	done

embench-clean-post:
	rm -f "$(EMBENCH_TOP)"/*.elf "$(EMBENCH_TOP)"/*.dis "$(EMBENCH_TOP)"/*.map
