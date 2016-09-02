#
# Copyright 2016 Ettus Research
#

#-------------------------------------------------
# Top-of-Makefile
#-------------------------------------------------
# Define BASE_DIR to point to the "top" dir
BASE_DIR = $(abspath ../../../top)
# Include viv_sim_preample after defining BASE_DIR
include $(BASE_DIR)/../tools/make/viv_sim_preamble.mak

#-------------------------------------------------
# Testbench Specific
#-------------------------------------------------
LIB_IP_DIR = $(BASE_DIR)/../lib/ip
IP_DIR = $(LIB_IP_DIR)

include $(LIB_IP_DIR)/complex_to_magphase/Makefile.inc
include $(LIB_IP_DIR)/phase_modulator/Makefile.inc

DESIGN_SRCS += $(abspath \
$(LIB_IP_COMPLEX_TO_MAGPHASE_SRCS) \
$(LIB_IP_PHASE_MODULATOR_SRCS) \
)

# Define only one toplevel module
SIM_TOP = noc_block_magphase_gain_tb

SIM_SRCS += \
$(abspath noc_block_magphase_gain_tb.sv) \
$(abspath ../noc_block_magphase_gain.v)

#-------------------------------------------------
# Bottom-of-Makefile
#-------------------------------------------------
# Include all simulator specific makefiles here
# Each should define a unique target to simulate
# e.g. xsim, vsim, etc and a common "clean" target
include $(BASE_DIR)/../tools/make/viv_simulator.mak
