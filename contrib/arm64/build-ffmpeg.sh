#!/usr/bin/env bash
set -euo pipefail
# Arguments are the architecture-independent root, dependency prefix and scratch directory.
root=$1
deps=$2
tmp=$3
src="$root/src/ExtLib/ffmpeg"
revision=11ef8d60d670b6908185a4780ad1a33b77783b0f
curl -fsSL --retry 3 "https://codeload.github.com/FFmpeg/FFmpeg/tar.gz/$revision" -o "$tmp/ffmpeg.tar.gz"
echo "26e5a531732219fa685b1b6e9a35f13ef71346ca9a16578088ae3c1fb9c19a39  $tmp/ffmpeg.tar.gz" | sha256sum -c -
mkdir "$tmp/upstream"
tar xf "$tmp/ffmpeg.tar.gz" --strip-components=1 -C "$tmp/upstream"

# Generate CPU and assembler feature definitions for the actual Windows target.
mkdir "$tmp/configure"
cd "$tmp/configure"
"$tmp/upstream/configure" --target-os=mingw32 --arch=aarch64 --enable-cross-compile \
    --cross-prefix=aarch64-w64-mingw32- --cc=aarch64-w64-mingw32-clang \
    --disable-everything --disable-autodetect --disable-programs --disable-doc \
    --disable-sve --disable-sve2 --disable-sme --disable-sme2

# Retain every MPC-BE-modified file, its codec registry and private headers.
# Upstream supplies all omitted source and the AArch64 makefiles and assembly.
cp -a "$src/." "$tmp/upstream/"
mv "$src" "$tmp/mpc-vendor"
mv "$tmp/upstream" "$src"
cd "$src"
python3 - "$tmp/configure/config.h" <<'PY'
from pathlib import Path
import re, sys
target = Path(sys.argv[1]).read_text()
features = re.compile(r'(?:ARCH_AARCH64|AS_ARCH_LEVEL|HAVE_(?:ARMV8|ARM_AES|ARM_CRC|VFP|NEON|DOTPROD|I8MM|PMULL|EOR3|SVE2?|SME2?|SME_I16I64)(?:_INLINE|_EXTERNAL)?|HAVE_AS_ARCH.*|HAVE_INTRINSICS_NEON|HAVE_INLINE_ASM|HAVE_FAST_64BIT|CONFIG_PIC)')
lines = []
for name, value in re.findall(r'^#define (\w+) (.+)$', target, re.M):
    if features.fullmatch(name):
        lines.extend([f'#undef {name}', f'#define {name} {value}'])
Path('config_arm64.h').write_text('\n'.join(lines) + '\n')
PY
cc=aarch64-w64-mingw32-clang
"$cc" -dM -E -include config.h -include config_components.h -x c /dev/null |
    awk '$1=="#define" && $2 ~ /^(CONFIG_|HAVE_|ARCH_)/ && $3=="1" {print $2 "=yes"}' > "$tmp/features.mak"

# swscale generates assembly using a native build-host tool.
cc -O2 -I. libswscale/aarch64/ops_static.c -o "$tmp/ops_static"
"$tmp/ops_static" > libswscale/aarch64/ops_neon.gen.S
for lib in libavcodec libavutil libavfilter libswresample libswscale; do
    make -s -f "$root/contrib/arm64/ffmpeg-objects.mak" list LIB="$lib" FEATURES="$tmp/features.mak"
done > "$tmp/dsp-objects"
mkdir -p "$tmp/dsp"
tr ' ' '\n' < "$tmp/dsp-objects" | sed '/^$/d' | sort -u > "$tmp/objects"
while read -r obj; do
    file="${obj%.o}"
    source="$file.S"
    [[ -f "$source" ]] || source="$file.c"
    mkdir -p "$tmp/dsp/$(dirname "$obj")"
    "$cc" -O3 -std=c17 -I. -Ilibavcodec -DHAVE_AV_CONFIG_H -D_WIN32_WINNT=0x0A00 \
        -D_WIN32_WINNT_WIN10=0x0A00 -D__USE_MINGW_ANSI_STDIO=0 -c "$source" -o "$tmp/dsp/$obj"
done < "$tmp/objects"
make -f ffmpeg.mak ARM64=yes -j"$(nproc)" "ARM64_INCLUDES=-I$deps/include"
out="$root/libarm64"
find "$tmp/dsp" -name '*.o' -print0 | xargs -0 llvm-ar rcs "$tmp/arm-dsp.a"
base="$root/_bin/lib/Release_ARM64/ffmpeg.lib"
printf 'CREATE %s\nADDLIB %s\nADDLIB %s\nSAVE\nEND\n' "$out/ffmpeg.lib" "$base" "$tmp/arm-dsp.a" | llvm-ar -M
"$cc" -std=c17 -O2 -I. "$root/contrib/arm64/ffmpeg-dsp.c" "$out/ffmpeg.lib" -lbcrypt -o "$out/ffmpeg-dsp-check.exe"
