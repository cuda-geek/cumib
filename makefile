#
# The MIT License (MIT)
#
# Copyright (c) 2013 cuda.geek (cuda.geek@gmail.com)
#
# Permission is hereby granted, free of charge, to any  person obtaining a copy of
# this software and  associated  documentation  files (the "Software"), to deal in
# the Software  without restriction,  including  without  limitation the rights to
# use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
# the Software, and to  permit persons  to whom the Software is furnished to do so,
# subject to the following conditions:
#
# The above copyright  notice and this  permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE  SOFTWARE IS  PROVIDED "AS IS",  WITHOUT WARRANTY  OF ANY  KIND,  EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
# FOR A PARTICULAR  PURPOSE AND  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
# COPYRIGHT HOLDERS BE LIABLE FOR ANY  CLAIM, DAMAGES  OR OTHER LIABILITY, WHETHER
# IN AN  ACTION OF  CONTRACT, TORT  OR  OTHERWISE,  ARISING  FROM,  OUT  OF  OR IN
# CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#

##################################################################################
# NOTE: This makefile requires CUDA compute capability greater of equal then 2.0
# because of device linking required for incremental build.
#
# This makefile works with cuda 5.5 targets folder.
#
#
# Variables used for cross-compilation:
# TARGET_NAME is a name of target OS. If does not specified, HOST_NANE is used.
# TARGET_ARCH is a target architecture. If does not specified, HOST_NANE is used.
# CUDA_ROOT is a path to CUDA installation. Default value is /usr/local/cuda.
# Override CXX, CXXFLAGS, LDFLAGS to make sure that compiler properly set.
#
# CUDA_GENERATION is a particular GPU architecture. Kepler  generation's sm_30  is
# the default. Values 20, 21, 30, 32, 35 are supported.
# CACHE_STRATEGY controls default caching. Use cache all (=ca) for L1 plot, cache
# global  (=cg) for L2 plot.
##################################################################################

suppoted_cuda_arch = 20 21 30 32 35 50

HOST_NAME = $(shell uname -s 2>/dev/null | tr "[:upper:]" "[:lower:]")
HOST_ARCH = $(shell uname -m | sed -e "s/i386/i686/")

CUDA_ROOT ?= /usr/local/cuda

TARGET_NAME ?= $(HOST_NAME)
TARGET_ARCH ?= $(HOST_ARCH)

CUDA_LIB_DIR = $(CUDA_ROOT)/targets/$(TARGET_ARCH)-$(TARGET_NAME)/lib

ifeq ($(TARGET_ARCH),armv7l)
CUDA_LIB_DIR = $(CUDA_ROOT)/targets/armv7-$(TARGET_NAME)-gnueabihf/lib
NVCC_FLAGS += --target-cpu-architecture=ARM -m32
LDFLAGS += -rpath=/usr/arm-linux-gnueabihf -rpath-link=/usr/arm-linux-gnueabihf
endif

CUDA_RT = cudart

HOST_CC=$(CXX)
DEVICE_CC = $(CUDA_ROOT)/bin/nvcc -ccbin $(HOST_CC)

CUDA_GENERATION ?= 30

ifeq ($(findstring $(CUDA_GENERATION),$(suppoted_cuda_arch)), )
$(error sm_$(CUDA_GENERATION) is not a valid archtecture or unsupported)
endif

virtual_arch = compute_$(CUDA_GENERATION)
binary_arch  = sm_$(CUDA_GENERATION)

ifeq ($(CUDA_GENERATION), 21)
virtual_arch = compute_20
endif

SRCS = global_load.cu laneid.cu mapped.cu operations.cu print_device_info.cu threshold.cu transpose.cu

BUILD_DIR := build

CACHE_STRATEGY ?= cg
NVCC_FLAGS += -gencode arch=$(virtual_arch),code=$(binary_arch) -Xptxas -dlcm=$(CACHE_STRATEGY)
# --verbose

all_targets = $(BUILD_DIR)/laneid-$(TARGET_ARCH) $(BUILD_DIR)/global-$(TARGET_ARCH) $(BUILD_DIR)/mapped-$(TARGET_ARCH)

################################################################################
# Targets
################################################################################

$(BUILD_DIR)/global-$(TARGET_ARCH): $(BUILD_DIR)/global_load.dev.o $(BUILD_DIR)/print_device_info.o $(BUILD_DIR)/global_load.o
	$(HOST_CC) $(CXXFLAGS) $(LDFLAGS) $^ -L $(CUDA_LIB_DIR) -l$(CUDA_RT) -o $@

$(BUILD_DIR)/mapped-$(TARGET_ARCH): $(BUILD_DIR)/mapped.o $(BUILD_DIR)/print_device_info.o $(BUILD_DIR)/mapped.dev.o
	$(HOST_CC) $(CXXFLAGS) $(LDFLAGS) $^ -L $(CUDA_LIB_DIR) -l$(CUDA_RT) -o $@

$(BUILD_DIR)/operations-$(TARGET_ARCH): $(BUILD_DIR)/operations.o $(BUILD_DIR)/print_device_info.o $(BUILD_DIR)/operations.dev.o
	$(HOST_CC) $(CXXFLAGS) $(LDFLAGS) $^ -L $(CUDA_LIB_DIR) -l$(CUDA_RT) -o $@

$(BUILD_DIR)/global_load.dev.o: $(BUILD_DIR)/global_load.o $(BUILD_DIR)/print_device_info.o
	$(DEVICE_CC) $(NVCC_FLAGS) $(CXXFLAGS) $(LDFLAGS) -dlink -o $@ $+

$(BUILD_DIR)/mapped.dev.o: $(BUILD_DIR)/mapped.o $(BUILD_DIR)/print_device_info.o
	$(DEVICE_CC) $(NVCC_FLAGS) $(CXXFLAGS) $(LDFLAGS) -dlink -o $@ $+

$(BUILD_DIR)/operations.dev.o: $(BUILD_DIR)/operations.o $(BUILD_DIR)/print_device_info.o
	$(DEVICE_CC) $(NVCC_FLAGS) $(CXXFLAGS) $(LDFLAGS) -dlink -o $@ $+

$(BUILD_DIR)/laneid-$(TARGET_ARCH): $(BUILD_DIR)/laneid.o
	$(DEVICE_CC) $(NVCC_FLAGS) $(CXXFLAGS) $(LDFLAGS) -L $(CUDA_LIB_DIR) laneid.cu -o $@

$(BUILD_DIR)/transpose-$(TARGET_ARCH): $(BUILD_DIR)/transpose.o $(BUILD_DIR)/print_device_info.o
	$(DEVICE_CC) $(NVCC_FLAGS) $(CXXFLAGS) $(LDFLAGS) -L $(CUDA_LIB_DIR)  $^  -o $@

$(BUILD_DIR)/threshold-$(TARGET_ARCH): $(BUILD_DIR)/threshold.o $(BUILD_DIR)/print_device_info.o
	$(DEVICE_CC) $(NVCC_FLAGS) $(CXXFLAGS) $(LDFLAGS) -L $(CUDA_LIB_DIR)  $^  -o $@

$(BUILD_DIR)/%.o: %.cu $(BUILD_DIR)/device_flags
	@mkdir -p $(@D)
	$(DEVICE_CC) $(NVCC_FLAGS) $(CXXFLAGS) $(LDFLAGS) -dc -o $@ $<

$(BUILD_DIR)/%.cu.d: %.cu
	@mkdir -p $(@D)
	$(SHELL) -ec '$(DEVICE_CC) -M $(NVCC_FLAGS) $(CXXFLAGS) $(LDFLAGS) $< |  sed -n "H;$$ {g;s@.*:\(.*\)@$< := \$$\(wildcard\1\)\n$*.o $@: $$\($<\)@;p}" > $@'

all: $(all_targets)

include $($(BUILD_DIR)/SRCS:.cu=.cu.d)

.PHONY: clean force

$(BUILD_DIR)/device_flags: force
	@mkdir -p $(@D)
	echo '$(NVCC_FLAGS)' | cmp -s - $@ || echo '$(NVCC_FLAGS)' > $@

clean:
	$(RM) -rf $(BUILD_DIR)
