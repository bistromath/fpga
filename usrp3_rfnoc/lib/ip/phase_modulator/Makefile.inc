#
# Copyright 2015 Ettus Research
#

include $(TOOLS_DIR)/make/viv_ip_builder.mak

LIB_IP_PHASE_MODULATOR_SRCS = $(IP_BUILD_DIR)/phase_modulator/phase_modulator.xci

LIB_IP_PHASE_MODULATOR_OUTS = $(addprefix $(IP_BUILD_DIR)/phase_modulator/, \
phase_modulator.xci.out \
synth/phase_modulator.vhd \
) 

$(LIB_IP_PHASE_MODULATOR_SRCS) $(LIB_IP_PHASE_MODULATOR_OUTS) : $(LIB_IP_DIR)/phase_modulator/phase_modulator.xci
	$(call BUILD_VIVADO_IP,phase_modulator,$(ARCH),$(PART_ID),$(LIB_IP_DIR),$(IP_BUILD_DIR),0)
