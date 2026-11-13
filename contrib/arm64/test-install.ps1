param([Parameter(Mandatory)][string]$Version)
$ErrorActionPreference = 'Stop'
$msi = (Resolve-Path "installer/MPC-BE.$Version.arm64.msi").Path
$folder = Join-Path $env:ProgramFiles 'MPC-BE ARM64'
$shortcut = Join-Path ([Environment]::GetFolderPath('CommonPrograms')) 'MPC-BE (ARM64).lnk'
function Invoke-Msi([string]$action, [string]$log) {
    $p = Start-Process msiexec.exe -ArgumentList @($action, ('"{0}"' -f $msi), '/qn', '/norestart', '/l*v', ('"{0}"' -f $log)) -Wait -PassThru
    if ($p.ExitCode -ne 0) { Get-Content $log -Tail 100; throw "Windows Installer exit $($p.ExitCode)" }
}
Invoke-Msi '/i' "$PWD/install.log"
try {
    $exe = Get-Item (Join-Path $folder 'mpc-be-arm64.exe')
    $info = $exe.VersionInfo
    $fileVersion = "$($info.FileMajorPart).$($info.FileMinorPart).$($info.FileBuildPart).$($info.FilePrivatePart)"
    if ($fileVersion -ne "$Version.0") { throw "Installed player version $fileVersion" }
    $app = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' |
        Where-Object DisplayName -eq 'MPC-BE (ARM64)'
    if ($app.DisplayVersion -ne $Version -or !(Test-Path $shortcut)) { throw 'Installed Apps or Start menu entry missing' }
    & ./contrib/arm64/test-playback.ps1 -PlayerDirectory $folder
} finally {
    $ini = Join-Path $folder 'mpc-be-arm64.ini'
    if (Test-Path $ini) { Remove-Item -LiteralPath $ini }
    Invoke-Msi '/x' "$PWD/uninstall.log"
}
if ((Test-Path $exe.FullName) -or (Test-Path $shortcut) -or (Test-Path $app.PSPath)) { throw 'Uninstall left a registered product, player or shortcut' }
Write-Host "Installed, played media with, and uninstalled MPC-BE $Version on Windows ARM64."
