param([string]$PlayerDirectory = "player", [string]$PlayerName = "mpc-be-arm64.exe", [switch]$Compatibility,
      [ValidateSet('Franky','Haali','madVR')][string]$ExternalRenderer, [switch]$Mvc, [switch]$Sources)
$ErrorActionPreference = 'Stop'
if ([Runtime.InteropServices.RuntimeInformation]::OSArchitecture -ne 'Arm64') { throw 'ARM64 Windows required' }
$exe = (Resolve-Path (Join-Path $PlayerDirectory $PlayerName)).Path
$images = @(Get-Item $exe) + @(Get-ChildItem $PlayerDirectory -Recurse -Include *.dll,*.ax)
if ($images.Count -lt 3) { throw 'Player resource DLLs are missing' }
$expected = if ($Compatibility) { 0x8664 } else { 0xaa64 }
foreach ($file in $images) {
    if (!$Compatibility -and $file.DirectoryName.StartsWith((Join-Path $PlayerDirectory Compatibility),[StringComparison]::OrdinalIgnoreCase)) { continue }
    $b = [IO.File]::ReadAllBytes($file.FullName)
    $pe = [BitConverter]::ToInt32($b, 0x3c)
    if ([BitConverter]::ToUInt32($b, $pe) -ne 0x4550 -or [BitConverter]::ToUInt16($b, $pe+4) -ne $expected) {
        throw "$($file.Name) has an unexpected PE architecture"
    }
}
Write-Host "Verified player and module PE headers for $PlayerDirectory."
# The uncompressed null renderer exercises decoding without requiring a VM sound device.
$ini = [IO.Path]::ChangeExtension($exe, '.ini')
$settings = @"
[Audio]
AudioRenderer=Null Audio Renderer (Uncompressed)
[Video]
VideoRenderer=11
[WebServer]
LocalhostOnly=1
"@
[IO.File]::WriteAllText($ini, $settings, [Text.Encoding]::Unicode)

function Test-Playback([string]$media, [int]$port, [string]$rendererModule, [int]$expectedDuration = 16000) {
    $name = [IO.Path]::GetFileName($media)
    $p = Start-Process $exe -ArgumentList @('/new','/play','/webport',$port,('"' + $media + '"')) -PassThru
    try {
        $before = $null
        $until = [DateTime]::UtcNow.AddSeconds(55)
        while ([DateTime]::UtcNow -lt $until) {
            if ($p.HasExited) { throw "Player exited with $($p.ExitCode)" }
            Start-Sleep -Milliseconds 500
            try { $html = (Invoke-WebRequest "http://127.0.0.1:$port/variables.html" -TimeoutSec 2).Content } catch { continue }
            if ($html -notmatch [regex]::Escape($name) -or $html -notmatch 'id="duration">(\d+)<') { continue }
            $duration = [int]$Matches[1]
            if ($duration -le 0 -or ($expectedDuration -gt 0 -and $duration -ne $expectedDuration)) { continue }
            if ($html -notmatch 'id="position">(\d+)<') { continue }
            $pos = [int]$Matches[1]
            if ($null -ne $before -and $pos -gt $before+500) {
                if ($rendererModule) {
                    $p.Refresh()
                    if ($rendererModule -notin $p.Modules.ModuleName) { throw "$rendererModule was not loaded" }
                    $frame = (Invoke-WebRequest "http://127.0.0.1:$port/snapshot.jpg" -TimeoutSec 5).Content
                    if ($frame.Length -lt 512 -or $frame[0] -ne 255 -or $frame[1] -ne 216) { throw 'No rendered JPEG frame' }
                    Write-Host "$rendererModule loaded and MPC-BE returned a $($frame.Length)-byte JPEG."
                }
                Write-Host "Player opened $name. Duration $duration ms. Position advanced from $before to $pos ms."
                return
            }
            if ($null -eq $before) { $before = $pos }
        }
        throw "No advancing playback observed. Last status: $html"
    } finally {
        if (!$p.HasExited) { $p.Kill(); $p.WaitForExit() }
    }

}

$port = 17581
if ($Sources) {
    $avisynth = Join-Path $env:RUNNER_TEMP 'AviSynthPlus_arm64.exe'
    Invoke-WebRequest 'https://github.com/AviSynth/AviSynthPlus/releases/download/v3.7.6/AviSynthPlus_3.7.6_20261025_arm64.exe' -OutFile $avisynth
    if ((Get-FileHash $avisynth).Hash -ne 'ccf9516e320a052a755be16090f0c6f048c19194899249360887d519838c2ccb') { throw 'Unexpected AviSynth+ installer' }
    $setup = Start-Process $avisynth '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' -Wait -PassThru
    if ($setup.ExitCode) { throw "AviSynth+ setup returned $($setup.ExitCode)" }
    $settings = $settings.Replace('VideoRenderer=11','VideoRenderer=5').Replace('LocalhostOnly=1',"LocalhostOnly=1`r`nEnablePreview=1")
    [IO.File]::WriteAllText($ini, $settings, [Text.Encoding]::Unicode)
    $avs = Join-Path $env:RUNNER_TEMP 'bars.avs'
    Set-Content $avs 'ColorBars(width=320,height=240).Trim(0,299).AssumeFPS(25)' -Encoding ascii
    Test-Playback $avs $port -rendererModule 'MpcScriptSource64.ax' -expectedDuration 12000
    $bmp = Join-Path $env:RUNNER_TEMP 'slide.bmp'
    Add-Type -AssemblyName System.Drawing
    $bitmap = [Drawing.Bitmap]::new(320,240)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $graphics.Clear([Drawing.Color]::CornflowerBlue)
    $graphics.Dispose()
    $bitmap.Save($bmp, [Drawing.Imaging.ImageFormat]::Bmp)
    $bitmap.Dispose()
    $imageSettings = 'HKCU:\Software\MPC-BE Filters\MPC Image Source'
    New-Item $imageSettings -Force | Out-Null
    New-ItemProperty $imageSettings -Name ImageDuration -PropertyType DWord -Value 6 -Force | Out-Null
    Test-Playback $bmp ($port+1) -rendererModule 'MpcImageSource64.ax' -expectedDuration 6000
    return
}
if ($Mvc) {
    $sample = Join-Path $env:RUNNER_TEMP 'small-00000.ssif'
    Invoke-WebRequest 'https://samples.ffmpeg.org/3D/small-00000.ssif' -OutFile $sample
    if ((Get-FileHash $sample).Hash -ne 'b08d8f72575cd1e8eb0cd66519dd56dbd1e742f0a0bb2d34436c32a0d5c266cd') { throw 'Unexpected MVC sample' }
    $settings = $settings.Replace('VideoRenderer=11','VideoRenderer=5').Replace('LocalhostOnly=1',"LocalhostOnly=1`r`nEnablePreview=1")
    $settings += "`r`n[InternalFilters]`r`nvdec_h264_mvc=1`r`n"
    [IO.File]::WriteAllText($ini, $settings, [Text.Encoding]::Unicode)
    Test-Playback $sample $port -rendererModule 'libmfxsw64.dll' -expectedDuration 0
    return
}
if ($ExternalRenderer) {
    $rendererId, $module = switch ($ExternalRenderer) {
        'Franky' { 8; 'FrankyRenderer.ax' }
        'Haali'  { 6; 'dxr.x64.dll' }
        'madVR'  { 7; 'madVR64.ax' }
    }
    $settings = $settings.Replace('VideoRenderer=11',"VideoRenderer=$rendererId").Replace('LocalhostOnly=1',"LocalhostOnly=1`r`nEnablePreview=1")
    [IO.File]::WriteAllText($ini, $settings, [Text.Encoding]::Unicode)
    Test-Playback (Resolve-Path 'media/h264.mp4').Path $port -rendererModule $module
    return
}
foreach ($name in 'tone.flac','h264.mp4','av1.mkv') {
    Test-Playback (Resolve-Path "media/$name").Path $port
    $port++
}

$settings = $settings.Replace('VideoRenderer=11','VideoRenderer=5').Replace('LocalhostOnly=1',"LocalhostOnly=1`r`nEnablePreview=1")
[IO.File]::WriteAllText($ini, $settings, [Text.Encoding]::Unicode)
Test-Playback (Resolve-Path 'media/h264.mp4').Path $port -rendererModule 'MpcVideoRenderer64.ax'
