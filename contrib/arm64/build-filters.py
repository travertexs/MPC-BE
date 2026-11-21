"""Build upstream's optional DirectShow filters for native Windows Arm."""
from pathlib import Path
import os
import shutil
import subprocess
import sys

components = [
    ('v0lt/ImageSourceFilter', 'f00eebc4676376f033ce5dcfd4b2fa3b0ab5f5e9', 'MpcImageSource'),
    ('v0lt/ScriptSourceFilter', '159c14ada4dd59502fa892a9e793edd6fb6e0353', 'MpcScriptSource'),
    ('Aleksoid1978/VideoRenderer', '6be828bfc415aa72286862e6e262eb652abd9a53', 'MpcVideoRenderer'),
]
stage = Path('filter-artifacts').resolve()
stage.mkdir(exist_ok=True)
temp = Path(os.environ['RUNNER_TEMP'])
msbuild = sys.argv[1]

def checkout(repo, sha):
    path = temp / repo.split('/')[1]
    subprocess.run(['git', 'init', '-q', path], check=True)
    subprocess.run(['git', 'fetch', '-q', '--depth=1', 'https://github.com/' + repo, sha], cwd=path, check=True)
    subprocess.run(['git', 'checkout', '-q', 'FETCH_HEAD'], cwd=path, check=True)
    return path

def build(root, project, *args):
    subprocess.run([msbuild, project, '/m:2', '/p:Configuration=Release', '/p:Platform=ARM64',
                    '/p:SolutionDir=' + str(root) + '\\', '/p:PlatformToolset=v143', '/v:minimal', *args],
                   cwd=root, check=True)

def edit(path, before, after):
    data = path.read_text(encoding='utf-8-sig')
    if before not in data:
        raise ValueError(f'{before!r} missing from {path}')
    path.write_text(data.replace(before, after), encoding='utf-8-sig')

for repo, sha, name in components:
    root = checkout(repo, sha)
    subprocess.run(['git', 'submodule', 'update', '--init', '--depth=1', 'external/BaseClasses'], cwd=root, check=True)
    for file in [root/'common.props', *root.glob('*/*.vcxproj')]:
        # These are disposable, architecture-specific builds of pinned source trees.
        data = file.read_text(encoding='utf-8-sig')
        file.write_text(data.replace('x64', 'ARM64').replace('MachineX64','MachineARM64'),encoding='utf-8-sig')
    if name == 'MpcVideoRenderer':
        # Use the ARM64 implementation for the renderer's existing fullscreen window hooks.
        hook = checkout('m417z/minhook-detours','e7d5427ede9e658f1810e742822fab2936e058da')
        build(hook, 'src/minhook-detours.vcxproj', '/p:ConfigurationType=StaticLibrary', '/p:TargetName=minhook-arm64')
        lib = next(hook.rglob('minhook-arm64.lib'))
        project = root/'Source/MpcVideoRenderer.vcxproj'
        edit(root/'common.props','/Zc:rvalueCast','/Zc:rvalueCast /Zc:preprocessor')
        data = project.read_text(encoding='utf-8-sig')
        start = data.index('    <ProjectReference Include="..\\external\\minhook.vcxproj">')
        end = data.index('</ProjectReference>', start) + len('</ProjectReference>')
        project.write_text(data[:start]+data[end:],encoding='utf-8-sig')
        edit(project,'<ModuleDefinitionFile>',f'<AdditionalDependencies>{lib};ntdll.lib;%(AdditionalDependencies)</AdditionalDependencies>\n      <ModuleDefinitionFile>')
        inc = root/'external/minhook/include'
        inc.mkdir(parents=True,exist_ok=True)
        shutil.copy(hook/'src/MinHook.h', inc)
        shutil.copy('include/sse2neon.h',root/'Source/Utils')
        edit(root/'Source/Helper.cpp','#include "Utils/gpu_memcpy_sse4.h"','#include "Utils/sse2neon.h"\n#define gpu_memcpy memcpy')
        cpu = root/'Source/Utils/CPUInfo.cpp'
        data = cpu.read_text()
        start = data.index('#ifdef _WIN32')
        end = data.index('static const bool bSSSE3',start)
        cpu.write_text(data[:start]+'// Byte shuffles in Helper.cpp use NEON on Arm.\nstatic const int nCPUFeatures = CPUInfo::CPU_SSSE3;\n'+data[end:])
        build(root,'Shaders/Shaders.vcxproj')
    build(root, f'Source/{name}.vcxproj')
    shutil.copy(next(root.rglob(name+'64.ax')),stage)
    for f in root.iterdir():
        if f.is_file() and any(token in f.name.lower() for token in ('license','copying')):
            shutil.copy(f,stage/(name+'-'+f.name))
    if name == 'MpcVideoRenderer':
        shutil.copy(hook/'LICENSE',stage/'minhook-detours-LICENSE.txt')
