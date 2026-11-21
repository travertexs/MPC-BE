$ErrorActionPreference = 'Stop'
$root = "$pwd\"
$vs = & "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -property installationPath
$msbuild = "$vs\MSBuild\Current\Bin\amd64\MSBuild.exe"
# Compile the upstream x64 static libraries for the optional hybrid player.
# An x64-only plug-in and its host share an ABI. Ordinary Arm64 libraries use a different ABI.
$env:_CL_ = '/GL-'
$project = 'src/apps/mplayerc/mpc-be.vcxproj'
# Build the MFC player itself as native ARM64EC; link its existing x64 static filter libraries.
$manifestPath = Join-Path $root 'src/apps/mplayerc/res/mpc-be.exe.manifest'
$manifest = [IO.File]::ReadAllText($manifestPath)
# Private x64 filters for the EC process. Keep system registration pointing at native Arm filters.
$private = @'
  <file name="MpcVideoRenderer64.ax">
    <comClass clsid="{71F080AA-8661-4093-B15E-4F6903E77D0A}" threadingModel="Both"/>
    <comClass clsid="{DA46D181-07D6-441D-B314-019AEB10148A}" threadingModel="Both"/>
    <comClass clsid="{D697132B-FCA4-4401-8869-D3B39D0750DB}" threadingModel="Both"/>
  </file>
  <file name="MpcImageSource64.ax">
    <comClass clsid="{7DB5C3B3-2419-4508-B1D0-F2D22DA8E439}" threadingModel="Both"/>
    <comClass clsid="{DF0FC50C-81CE-4141-9BC3-0BEB233181BB}" threadingModel="Both"/>
  </file>
  <file name="MpcScriptSource64.ax">
    <comClass clsid="{7D3BBD5A-880D-4A30-A2D1-7B8C2741AFEF}" threadingModel="Both"/>
    <comClass clsid="{D36E542D-8645-4F2C-A758-55C6FDF67E50}" threadingModel="Both"/>
  </file>
'@
[IO.File]::WriteAllText($manifestPath,$manifest.Replace('</assembly>',"$private</assembly>"))
[xml]$xml = Get-Content $project -Raw
$ns = $xml.DocumentElement.NamespaceURI
foreach ($ref in @($xml.SelectNodes("//*[local-name()='ProjectReference']"))) { [void]$ref.ParentNode.RemoveChild($ref) }
$ecProject = "$root\src\apps\mplayerc\mpc-be-ec.vcxproj"
$s = $xml.OuterXml.Replace('Release|x64', 'Release|ARM64EC').Replace('>x64<','>ARM64EC<').Replace("'=='x64'", "'=='ARM64EC'")
$s = $s.Replace('_bin\lib\$(Configuration)_$(Platform)', '_bin\lib\Release_x64')
$libs = (Get-ChildItem _bin/lib/Release_x64 -Filter *.lib).FullName -join ';'
if (!$libs) {throw 'x64 static filter libraries missing'}
$s = $s.Replace('libgcc.a;libmingwex.a;', "$libs;libgcc.a;libmingwex.a;")
[IO.File]::WriteAllText($ecProject,$s)
& $msbuild $ecProject /m:2 /p:Configuration=Release /p:Platform=ARM64EC "/p:SolutionDir=$root" "/p:OutDir=$root\ec-player\" /p:TargetName=mpc-be64 /p:CL_MPCount=2 /v:minimal
if ($LASTEXITCODE) { exit $LASTEXITCODE }

$dumpbin = Get-ChildItem "$vs/VC/Tools/MSVC/*/bin/Hostx64/x64/dumpbin.exe" | Sort-Object FullName -Descending | Select-Object -First 1
$headers = & $dumpbin.FullName /headers /loadconfig ec-player/mpc-be64.exe
if ($LASTEXITCODE -or !($headers -match '8664 machine \(x64\) \(ARM64X\)')) {
    throw 'The compatibility player has no ARM64EC hybrid image metadata'
}
$headers | Select-String -Pattern 'ARM64X|CHPE metadata' | Write-Host

git submodule update --init --depth 1 -- distrib/MPC_components
if ($LASTEXITCODE) {exit $LASTEXITCODE}
foreach ($filter in 'MpcVideoRenderer','MpcImageSource','MpcScriptSource') {
    Copy-Item "distrib/MPC_components/$filter/$($filter)64.ax" ec-player/
}
Copy-Item distrib/MPC_components/IntelMediaSDK/libmfxsw64.dll ec-player/
& $msbuild src/apps/mpciconlib/mpciconlib.vcxproj /p:Configuration=Release /p:Platform=x64 "/p:SolutionDir=$root" /v:quiet
if ($LASTEXITCODE) {exit $LASTEXITCODE}
Copy-Item _bin/mpc-be_x64/mpciconlib.dll ec-player/
$resources = 'src/apps/mpcresources/mpcresources.vcxproj'
foreach ($config in (([xml](Get-Content $resources -Raw)).Project.ItemGroup.ProjectConfiguration | Where-Object Platform -eq x64)) {
    & $msbuild $resources "/p:Configuration=$($config.Configuration)" /p:Platform=x64 "/p:SolutionDir=$root" /v:quiet
    if ($LASTEXITCODE) {exit $LASTEXITCODE}
}
Copy-Item _bin/mpc-be_x64/Lang ec-player/ -Recurse
