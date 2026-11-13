#include <stdio.h>
#include "libavutil/cpu.h"
#include "libavutil/float_dsp.h"
#include "libavutil/mem.h"

extern void ff_vector_fmul_neon(float *, const float *, const float *, int);

int main(void)
{
    _Alignas(32) float x[32], y[32], result[32];
    AVFloatDSPContext *dsp = avpriv_float_dsp_alloc(1);
    if (!dsp || !(av_get_cpu_flags() & AV_CPU_FLAG_NEON) ||
        dsp->vector_fmul != ff_vector_fmul_neon)
        return 1;
    for (int i = 0; i < 32; ++i) {
        x[i] = i - 8;
        y[i] = i + 2;
    }
    dsp->vector_fmul(result, x, y, 32);
    for (int i = 0; i < 32; ++i)
        if (result[i] != x[i] * y[i])
            return 2;
    av_free(dsp);
    puts("FFmpeg detected NEON, dispatched ff_vector_fmul_neon, and verified all 32 products.");
    return 0;
}
