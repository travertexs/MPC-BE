$ErrorActionPreference = 'Stop'
if ([Runtime.InteropServices.RuntimeInformation]::OSArchitecture -ne 'Arm64') { throw 'ARM64 Windows required' }
$exe = (Resolve-Path player/mpc-be-arm64.exe).Path
$b = [IO.File]::ReadAllBytes($exe)
$pe = [BitConverter]::ToInt32($b, 0x3c)
if ([BitConverter]::ToUInt32($b, $pe) -ne 0x4550 -or [BitConverter]::ToUInt16($b, $pe+4) -ne 0xaa64) {
    throw 'Player must be an ARM64 PE image'
}
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

function Test-Playback([string]$media, [int]$port) {
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
foreach ($name in 'tone.flac','h264.mp4','av1.mkv') {
    Test-Playback (Resolve-Path "media/$name").Path $port
    $port++
}
