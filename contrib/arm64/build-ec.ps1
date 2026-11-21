$ErrorActionPreference = 'Stop'
$root = "$pwd\"
$vs = & "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -property installationPath
$msbuild = "$vs\MSBuild\Current\Bin\amd64\MSBuild.exe"
# Compile the upstream x64 static libraries for the optional hybrid player.
# An x64-only plug-in and its host share an ABI. Ordinary Arm64 libraries use a different ABI.
$env:_CL_ = '/GL-'
$project = 'src/apps/mplayerc/mpc-be.vcxproj'
& $msbuild $project /m:3 /p:Configuration=Release /p:Platform=x64 "/p:SolutionDir=$root" /p:CL_MPCount=2 /v:minimal
if ($LASTEXITCODE) { exit $LASTEXITCODE }
# Build the MFC player itself as native ARM64EC; link its existing x64 static filter libraries.
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
