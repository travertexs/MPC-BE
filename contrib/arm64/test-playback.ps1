param([string]$PlayerDirectory = "player", [string]$PlayerName = "mpc-be-arm64.exe", [switch]$Compatibility, [switch]$Franky)
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

function Test-Playback([string]$media, [int]$port, [string]$rendererModule) {
    $name = [IO.Path]::GetFileName($media)
    $p = Start-Process $exe -ArgumentList @('/new','/play','/webport',$port,('"' + $media + '"')) -PassThru
    try {
        $before = $null
        $until = [DateTime]::UtcNow.AddSeconds(55)
        while ([DateTime]::UtcNow -lt $until) {
            if ($p.HasExited) { throw "Player exited with $($p.ExitCode)" }
            Start-Sleep -Milliseconds 500
            try { $html = (Invoke-WebRequest "http://127.0.0.1:$port/variables.html" -TimeoutSec 2).Content } catch { continue }
            if ($html -notmatch [regex]::Escape($name) -or $html -notmatch 'id="duration">(\d+)<' -or [int]$Matches[1] -ne 16000) { continue }
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
                Write-Host "ARM64 player opened $name. Duration 16000 ms. Position advanced from $before to $pos ms."
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
if ($Franky) {
    $settings = $settings.Replace('VideoRenderer=11','VideoRenderer=8').Replace('LocalhostOnly=1',"LocalhostOnly=1`r`nEnablePreview=1")
    [IO.File]::WriteAllText($ini, $settings, [Text.Encoding]::Unicode)
    Test-Playback (Resolve-Path 'media/h264.mp4').Path $port -rendererModule 'FrankyRenderer.ax'
    return
}
foreach ($name in 'tone.flac','h264.mp4','av1.mkv') {
    Test-Playback (Resolve-Path "media/$name").Path $port
    $port++
}

$settings = $settings.Replace('VideoRenderer=11','VideoRenderer=5').Replace('LocalhostOnly=1',"LocalhostOnly=1`r`nEnablePreview=1")
[IO.File]::WriteAllText($ini, $settings, [Text.Encoding]::Unicode)
Test-Playback (Resolve-Path 'media/h264.mp4').Path $port -rendererModule 'MpcVideoRenderer64.ax'
