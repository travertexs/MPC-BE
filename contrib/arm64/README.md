# MPC-BE for Windows on Arm

The `arm64/upstream` branch follows MPC-BE development. Version 1.9.3.30 incorporates upstream revision [601f477](https://github.com/Aleksoid1978/MPC-BE/commit/601f4772c0ffaadd8088089e4d4460af6a8e7ff7).

## Installation

Open the release EXE to start the upstream interactive setup wizard. Choose **MPC-BE arm64** in the Start menu for normal playback. To choose a renderer, open **View → Options → Video**. MPC Video Renderer is selected for installation by default. The custom installation includes checkboxes for MPC Script Source and MPC Image Source.

Setup uses the upstream 64-bit installer identity, registry view, settings and `mpc-be64.exe` filename. The default location is `Program Files\MPC-BE`. Setup reuses the directory selected for a previous x64 installation and removes the original ARM64 MSI after the user confirms installation. Installed apps shows **MPC-BE arm64 1.9.3.30**.

## Video renderers and plug-ins

| Component | How to use it on Windows 11 Arm |
| --- | --- |
| Enhanced Video Renderer, EVR custom presenter, Sync Video Renderer and the two null renderers | Available in the native player's Video options. |
| MPC Video Renderer | Select the component in setup, then select the renderer in Video options. The renderer, its pixel conversion routines and its fullscreen hooks are compiled for ARM64. |
| MPC Script Source and MPC Image Source | Select the relevant component in setup. These filters are compiled for ARM64. The script filter uses AviSynth's C interface with the official Windows ARM64 runtime. Install the interpreter separately for the scripts you use. [AviSynth+ ARM64 release](https://github.com/AviSynth/AviSynthPlus/releases/tag/v3.7.6) |
| VapourSynth scripts | VapourSynth R82 ships a Windows x64 runtime. Use that runtime with MPC Script Source in the compatibility player. [VapourSynth R82](https://github.com/vapoursynth/vapoursynth/releases/tag/R82) |
| x64-only external renderers including Haali, madVR and FrankyRenderer | Install the renderer separately as for upstream x64. Open **MPC-BE arm64 (x64 plug-ins)** from the Start menu, then select it in Video options. Availability depends on the renderer, graphics driver and device. |
| Intel MVC and Logitech LCD | The compatibility player includes upstream's Intel MVC software runtime and links its Logitech LCD SDK. Device-specific functionality requires the corresponding hardware or software. |

The default player, its internal codecs and its bundled DirectShow filters are native ARM64. The second player runs a native ARM64EC build of the application with upstream x64 codec and filter libraries. Windows runs its x64 code under emulation. The compatibility player lives under `Compatibility` in the same installation. Its private x64 filters use an application manifest so the main player can keep the native filters registered.

## Native dependencies

| Component | Implementation |
| --- | --- |
| FFmpeg | The build starts from FFmpeg revision `e8574d0b22`, overlays MPC-BE's matching modifications and codec registrations, and builds its AArch64 and NEON implementations for Windows. |
| dav1d and FDK AAC | dav1d 1.5.5 includes AArch64 assembly. FDK AAC 2.0.3 is compiled with the Windows ARM64 C++ toolchain. |
| MFC, ATL, Windows SDK and DirectShow | Microsoft's ARM64 compiler and libraries plus the pinned DirectShow BaseClasses source. |
| Audio, pixel conversion and subtitles | Existing SSE intrinsics above the codec layer map to NEON through the pinned sse2neon header. Subtitle routines with an AVX2 variant use the 128-bit implementation. |
| Other internal libraries | The native build compiles the repository's FLAC, SoXR, Speex, PNG, zlib, Little CMS, MediaInfo, ZenLib, Bento4, Detours, uavs3d and vvdec sources. |

## Cloud verification

GitHub Actions builds the application on Ubuntu and Windows. A Windows 11 Arm runner drives the setup wizard, checks upgrades and reads the renderer choices from the installed application. It plays FLAC, H.264 and AV1 media and checks that the playback clock advances.

The playback jobs select MPC Video Renderer in both players and test the x64 Haali, madVR and FrankyRenderer releases in the compatibility player. They check the loaded renderer module and retrieve a rendered JPEG from MPC-BE. The native source filters are exercised with an AviSynth+ script and a bitmap. A stereoscopic H.264 sample exercises the Intel software MVC runtime. Physical HDR displays, protected HDMI paths and keyboard LCDs require hardware testing.
