# Evaluate the pinned FFmpeg architecture makefiles with MPC-BE's enabled codecs.
# Run separately for each library so its OBJS and conditional variables stay local.
include $(FEATURES)
ifeq ($(LIB),libavcodec)
# MPC-BE lists both generic DSP objects directly in ffmpeg.mak.
CONFIG_MPEGVIDEOENCDSP := yes
CONFIG_VP8DSP := yes
endif
include $(LIB)/aarch64/Makefile
-include $(LIB)/neon/Makefile
include ffbuild/arch.mak

.PHONY: list
list:
	@echo $(addprefix $(LIB)/,$(sort $(OBJS) $(OBJS-yes)))
