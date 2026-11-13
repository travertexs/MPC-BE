# MPC-BE for Windows on Arm

The `windows-arm64` branch builds the upstream MFC player, DirectShow filters and resources for the ARM64 ABI. Extract the entire portable package into one folder and launch `mpc-be-arm64.exe`. The English UI is embedded in the player. The other upstream languages are in the `Lang` folder.

## Build and runtime checks

The Windows ARM64 workflow cross-compiles the vendored FFmpeg source on Ubuntu with LLVM-MinGW targeting Windows UCRT. Visual Studio 2022 on a Windows runner compiles the player, filters and resource DLLs for ARM64 and links the native codec archives. The playback job downloads the same package on a GitHub-hosted Windows 11 Arm machine. It checks the PE machine fields and uses MPC-BE's web interface on loopback to confirm the file name, media duration and advancing playback position. The fixtures contain FLAC audio, H.264 in MP4 and AV1 in Matroska. The uncompressed null renderers let the test exercise decoding without requiring physical speakers or a GPU display.

## Dependencies

| Component | Windows ARM64 implementation |
| --- | --- |
| FFmpeg | MPC-BE's patched codec and processing sources, using their portable C implementations. The upstream MPC-BE source snapshot omits most of FFmpeg's AArch64 DSP backends. |
| dav1d and FDK AAC | The workflow builds dav1d 1.5.4 and FDK AAC 2.0.3 from source for ARM64 and compiles the FFmpeg interfaces against the matching headers. dav1d includes AArch64 assembly. |
| MFC, ATL, Windows SDK and DirectShow | Microsoft's ARM64 compiler, static libraries and SDK imports. The DirectShow BaseClasses sources come from MPC-BE's pinned submodule. |
| Audio, pixel conversion and subtitle routines | Existing SSE intrinsics above the codec layer compile to Arm instructions through a pinned sse2neon header. AVX2-only subtitle routines use the 128-bit implementation on Arm. |
| Other internal libraries | The Visual Studio build compiles the repository's FLAC, SoXR, Speex, PNG, zlib, Little CMS, MediaInfo, ZenLib, Bento4, Detours, uavs3d and vvdec sources for ARM64. Architecture-specific filters and libraries use their portable implementations where necessary. |
| Logitech LCD | The repository ships an Intel-architecture lgLcd SDK library. The ARM64 player omits the optional keyboard LCD integration. |

Intel Media SDK MVC decoding requires Intel's external runtime. Third-party DirectShow filters loaded into this player also need a compatible ARM64 binary. The package uses Windows' built-in rendering facilities and does not bundle the upstream x86 or x64 optional renderer DLLs.
