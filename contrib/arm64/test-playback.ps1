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
[IO.File]::WriteAllText($ini, "[Audio]\r\nAudioRenderer=Null Audio Renderer (Uncompressed)\r\n".Replace('\r\n', [Environment]::NewLine), [Text.Encoding]::Unicode)
$media = Join-Path $PWD 'tone.wav'
$rate = 8000
$samples = $rate * 16
$w = [IO.BinaryWriter]::new([IO.File]::Create($media))
try {
    $w.Write([Text.Encoding]::ASCII.GetBytes('RIFF'))
    $w.Write([int](36 + 2*$samples))
    $w.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt '))
    $w.Write([int]16)
    $w.Write([int16]1)
    $w.Write([int16]1)
    $w.Write([int]$rate)
    $w.Write([int](2*$rate))
    $w.Write([int16]2)
    $w.Write([int16]16)
    $w.Write([Text.Encoding]::ASCII.GetBytes('data'))
    $w.Write([int](2*$samples))
    for ($i=0; $i -lt $samples; $i++) { $w.Write([int16](1000*[Math]::Sin($i*2*[Math]::PI*440/$rate))) }
} finally { $w.Dispose() }
$p = Start-Process $exe -ArgumentList @('/new','/play','/webport','17581',('"' + $media + '"')) -PassThru
try {
    $before = $null
    $until = [DateTime]::UtcNow.AddSeconds(55)
    while ([DateTime]::UtcNow -lt $until) {
        if ($p.HasExited) { throw "Player exited with $($p.ExitCode)" }
        Start-Sleep -Milliseconds 500
        try { $html = (Invoke-WebRequest 'http://127.0.0.1:17581/variables.html' -TimeoutSec 2).Content } catch { continue }
        if ($html -notmatch 'tone\.wav' -or $html -notmatch 'id="duration">(\d+)<' -or [int]$Matches[1] -ne 16000) { continue }
        if ($html -notmatch 'id="position">(\d+)<') { continue }
        $pos = [int]$Matches[1]
        if ($null -ne $before -and $pos -gt $before+500) {
            Write-Host "ARM64 player opened tone.wav. Duration 16000 ms. Position advanced from $before to $pos ms."
            return
        }
        if ($null -eq $before) { $before = $pos }
    }
    throw "No advancing playback observed. Last status: $html"
} finally {
    if (!$p.HasExited) { $p.Kill(); $p.WaitForExit() }
}
