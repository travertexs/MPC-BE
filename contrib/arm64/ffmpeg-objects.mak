# Evaluate the pinned FFmpeg architecture makefiles with MPC-BE's enabled codecs.
# Run separately for each library so its OBJS and conditional variables stay local.
include $(FEATURES)
include $(LIB)/aarch64/Makefile
include ffbuild/arch.mak

.PHONY: list
list:
	@echo $(addprefix $(LIB)/,$(sort $(OBJS) $(OBJS-yes)))
