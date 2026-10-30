# SPDX-License-Identifier: Apache-2.0
ROOT := $(abspath ..)
HERE := $(CURDIR)
HARTS ?= 1
ISSUE_METHOD ?= 1
CACHE ?= 0
ITERATIONS ?= 1
TOTAL_ITERATIONS ?=
IMAGE_STRIDE ?= 0x100000
STACK_SIZE ?= 0x4000
CLOCK_MHZ ?= 80
BUILD ?= $(HERE)/build/h$(HARTS)
override BUILD := $(abspath $(BUILD))
TINY_DIR ?= $(HERE)/.deps/tiny
TFLM_DIR ?= $(HERE)/.deps/tflm
PYTHON ?= python3
HOST_CXX ?= g++
RISCV_TOOLS ?= riscv64-unknown-elf
CC := $(RISCV_TOOLS)-gcc
CXX := $(RISCV_TOOLS)-g++
OBJCOPY := $(RISCV_TOOLS)-objcopy
OBJDUMP := $(RISCV_TOOLS)-objdump
VERILATOR ?= verilator
JOBS ?= 2
TIMEOUT ?= 900

TFLM_MICRO := $(TFLM_DIR)/tensorflow/lite/micro
TFLM_REL_SRCS := \
  flatbuffer_conversions.cc flatbuffer_utils.cc memory_helpers.cc \
  micro_allocation_info.cc micro_allocator.cc micro_common.cc micro_context.cc \
  micro_interpreter.cc micro_interpreter_context.cc micro_interpreter_graph.cc \
  micro_log.cc micro_op_resolver.cc micro_resource_variable.cc micro_utils.cc \
  arena_allocator/non_persistent_arena_buffer_allocator.cc \
  arena_allocator/persistent_arena_buffer_allocator.cc \
  arena_allocator/single_arena_buffer_allocator.cc \
  memory_planner/greedy_memory_planner.cc memory_planner/linear_memory_planner.cc \
  memory_planner/non_persistent_buffer_planner_shim.cc \
  kernels/kernel_util.cc kernels/fully_connected.cc kernels/fully_connected_common.cc \
  kernels/quantize.cc kernels/quantize_common.cc \
  kernels/dequantize.cc kernels/dequantize_common.cc \
  kernels/internal/common.cc kernels/internal/portable_tensor_utils.cc \
  kernels/internal/quantization_util.cc kernels/internal/tensor_ctypes.cc
TFLM_HOST_OBJS := $(addprefix $(BUILD)/host/tflm/,$(TFLM_REL_SRCS:.cc=.o))
TFLM_RV_OBJS := $(addprefix $(BUILD)/rv/tflm/,$(TFLM_REL_SRCS:.cc=.o))
INCLUDES := -I$(HERE) -I$(BUILD) -I$(TFLM_DIR) \
  -I$(TFLM_MICRO)/tools/make/downloads/flatbuffers/include
COMMON := -O3 -ffunction-sections -fdata-sections -ffp-contract=off \
  -DTF_LITE_STATIC_MEMORY -DFLATBUFFERS_LOCALE_INDEPENDENT=0
CXX_COMMON := $(COMMON) -std=c++17 -fno-exceptions -fno-rtti \
  -fno-threadsafe-statics -fno-use-cxa-atexit
RV := -march=rv32im -mabi=ilp32 -misa-spec=2.2 -mcmodel=medany -mstrict-align
RV_CONFIG := -include $(BUILD)/tiny_config.h
RV_CFLAGS := $(COMMON) $(RV) $(RV_CONFIG) -std=gnu99 -ffreestanding -I$(ROOT)/sw/system
RV_CXXFLAGS := $(CXX_COMMON) $(RV) $(RV_CONFIG) -ffreestanding -DTF_LITE_USE_GLOBAL_CMATH_FUNCTIONS
DEPFLAGS := -MMD -MP
HOST_SHARED := $(BUILD)/host/model_runner.o $(BUILD)/host/model_data.o $(BUILD)/host/input_data.o
RV_SHARED := $(BUILD)/rv/model_runner.o $(BUILD)/rv/model_data.o $(BUILD)/rv/input_data.o
RV_OBJS := $(TFLM_RV_OBJS) $(RV_SHARED) $(BUILD)/rv/benchmark_main.o \
  $(BUILD)/rv/target_log.o $(BUILD)/runtime.o $(BUILD)/startup.o $(BUILD)/descriptor.o

.PHONY: all
all: $(BUILD)/tiny.elf
$(BUILD)/host/tflm/%.o: $(TFLM_MICRO)/%.cc
	@mkdir -p $(@D)
	$(HOST_CXX) $(CXX_COMMON) $(INCLUDES) $(DEPFLAGS) -c $< -o $@
$(BUILD)/rv/tflm/%.o: $(TFLM_MICRO)/%.cc $(BUILD)/tiny_config.h
	@mkdir -p $(@D)
	$(CXX) $(RV_CXXFLAGS) $(INCLUDES) $(DEPFLAGS) -c $< -o $@
$(BUILD)/host/model_data.o: $(BUILD)/model_data.cc
	@mkdir -p $(@D)
	$(HOST_CXX) $(CXX_COMMON) $(INCLUDES) $(DEPFLAGS) -c $< -o $@
$(BUILD)/host/input_data.o: $(BUILD)/input_data.cc
	@mkdir -p $(@D)
	$(HOST_CXX) $(CXX_COMMON) $(INCLUDES) $(DEPFLAGS) -c $< -o $@
$(BUILD)/rv/model_data.o: $(BUILD)/model_data.cc $(BUILD)/tiny_config.h
	@mkdir -p $(@D)
	$(CXX) $(RV_CXXFLAGS) $(INCLUDES) $(DEPFLAGS) -c $< -o $@
$(BUILD)/rv/input_data.o: $(BUILD)/input_data.cc $(BUILD)/tiny_config.h
	@mkdir -p $(@D)
	$(CXX) $(RV_CXXFLAGS) $(INCLUDES) $(DEPFLAGS) -c $< -o $@
$(BUILD)/host/%.o: %.cc
	@mkdir -p $(@D)
	$(HOST_CXX) $(CXX_COMMON) $(INCLUDES) $(DEPFLAGS) -c $< -o $@
$(BUILD)/rv/%.o: %.cc $(BUILD)/tiny_config.h
	@mkdir -p $(@D)
	$(CXX) $(RV_CXXFLAGS) $(INCLUDES) $(DEPFLAGS) -c $< -o $@
$(BUILD)/rv/benchmark_main.o: benchmark_main.cc $(BUILD)/golden.h $(BUILD)/tiny_config.h
	@mkdir -p $(@D)
	$(CXX) $(RV_CXXFLAGS) $(INCLUDES) $(DEPFLAGS) -c $< -o $@
$(BUILD)/rv/%.o: %.c $(BUILD)/tiny_config.h
	@mkdir -p $(@D)
	$(CC) $(RV_CFLAGS) $(INCLUDES) $(DEPFLAGS) -c $< -o $@
$(BUILD)/host_reference: $(TFLM_HOST_OBJS) $(HOST_SHARED) $(BUILD)/host/host_reference.o $(BUILD)/host/debug_log.o
	$(HOST_CXX) -Wl,--gc-sections $^ -lm -o $@
$(BUILD)/host/debug_log.o: $(TFLM_MICRO)/debug_log.cc
	@mkdir -p $(@D)
	$(HOST_CXX) $(CXX_COMMON) $(INCLUDES) $(DEPFLAGS) -c $< -o $@
$(BUILD)/golden.h: $(BUILD)/host_reference
	$(BUILD)/host_reference > $@.tmp 2> $(BUILD)/host_reference.log
	mv $@.tmp $@

$(BUILD)/tiny.elf: $(RV_OBJS) ../link.ld
	$(CXX) $(RV) -static -nostartfiles -Wl,--gc-sections -T ../link.ld -Wl,-Map=$(BUILD)/tiny.map $(RV_OBJS) -Wl,--start-group -lc -lm -lgcc -Wl,--end-group -o $@
-include $(wildcard $(BUILD)/host/*.d $(BUILD)/rv/*.d)
-include $(TFLM_HOST_OBJS:.o=.d) $(TFLM_RV_OBJS:.o=.d)
