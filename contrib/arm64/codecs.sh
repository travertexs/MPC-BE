#!/usr/bin/env bash
set -euo pipefail
root=$(pwd)
out="$root/libarm64"
mkdir -p "$out"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"
archive=llvm-mingw-20261104-ucrt-ubuntu-22.04-x86_64.tar.xz
curl -fsSL --retry 3 "https://github.com/mstorsjo/llvm-mingw/releases/download/20261104/$archive" -o "$archive"
echo "919380403de87dca3c581c2053230cd298af5e891286628ba0613b7fed370926  $archive" | sha256sum -c -
tar xf "$archive"
export PATH="$tmp/$(basename "$archive" .tar.xz)/bin:$PATH"
target=aarch64-w64-mingw32
# Build AV1 with dav1d's AArch64 assembly and compile against its own installed headers.
git clone -q --depth 1 --branch 1.5.4 https://github.com/videolan/dav1d.git
test "$(git -C dav1d rev-parse HEAD)" = 54706fc6bc0cdecab7e9593974a4039cc038fca7
cat > windows-arm64.ini <<EOF
[binaries]
c = '$target-clang'
ar = 'llvm-ar'
strip = 'llvm-strip'
windres = '$target-windres'
[host_machine]
system = 'windows'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
EOF
meson setup dav1d-build dav1d --cross-file windows-arm64.ini --buildtype release --default-library static -Denable_tools=false -Denable_tests=false --prefix="$tmp/deps"
meson install -C dav1d-build
cp "$(find "$tmp/deps" -name libdav1d.a -print -quit)" "$out/"
cp "$($target-clang -print-file-name=libmingwex.a)" "$out/"
cp "$($target-clang -print-libgcc-file-name)" "$out/libbuiltins.a"
# Prepend installed public headers so the structures match the linked libraries.
export CPATH="$tmp/deps/include"
make -C "$root/src/ExtLib/ffmpeg" -f ffmpeg.mak ARM64=yes -j"$(nproc)" "ARM64_INCLUDES=-I$tmp/deps/include"
cp "$root/_bin/lib/Release_ARM64/ffmpeg.lib" "$out/"
