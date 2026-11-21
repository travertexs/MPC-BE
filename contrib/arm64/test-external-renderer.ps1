param([Parameter(Mandatory)][ValidateSet('Haali', 'madVR', 'Franky')][string]$Renderer)
$ErrorActionPreference = 'Stop'
$fixture = Join-Path $env:RUNNER_TEMP $Renderer
$setup = Get-ChildItem installer/*.exe
$proc = Start-Process $setup.FullName '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /LANG=en' -Wait -PassThru
if ($proc.ExitCode) { throw "Setup returned $($proc.ExitCode)" }
switch ($Renderer) {
    'Franky' {
        $url = 'https://github.com/mryx007/FrankyRenderer/releases/download/v1.2.2/FrankyRenderer-1.2.2-x64.zip'
        $sha = '4b525ea1e23b7b672dfe5942b9a74ad459c968594a89264a74c05deff58adaed'
        $module = 'FrankyRenderer.ax'
        $label = 'FrankyRenderer'
    }
    'Haali' {
        $url = 'https://haali.net/mkv/MatroskaSplitter.exe'
        $sha = '2fbfe6761c98b332b4342353be2cef945d6a1e46bb5c7c406e6f0eb4c92db07d'
        $module = 'splitter.x64.ax'
        $label = 'Haali Video Renderer'
    }
    'madVR' {
        $url = 'https://madshi.net/madVR.zip'
        $sha = '336651a376890dfb56d4f14871f4e8c7d495d79ceb4d0d69a48f62236f4af623'
        $module = 'madVR64.ax'
        $label = 'madVR'
    }
}
$package = Join-Path $env:RUNNER_TEMP ([uri]$url).Segments[-1]
curl.exe -fLsS --retry 3 $url -o $package
if ($LASTEXITCODE -or (Get-FileHash $package).Hash -ne $sha) { throw "Unable to verify $Renderer vendor package" }
7z x $package "-o$fixture" -bso0 -y
if ($LASTEXITCODE) { throw "Unable to extract $Renderer" }
$ax = Get-ChildItem $fixture -Recurse -Filter $module | Select-Object -First 1
if (!$ax) { throw "Missing $module in $fixture" }
$proc = Start-Process regsvr32.exe "/s `"$($ax.FullName)`"" -Wait -PassThru
if ($proc.ExitCode) { throw "Registering $module returned $($proc.ExitCode)" }
$folder = Join-Path $env:ProgramFiles 'MPC-BE/Compatibility'
python ./contrib/arm64/test-renderer-ui.py "$folder/mpc-be64.exe" $label
if ($LASTEXITCODE) { throw "$label missing from the compatible player's Video options" }
& ./contrib/arm64/test-playback.ps1 -PlayerDirectory $folder -PlayerName mpc-be64.exe -Compatibility -ExternalRenderer $Renderer
