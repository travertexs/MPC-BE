param([Parameter(Mandatory)][string]$Version)
$ErrorActionPreference = 'Stop'
$setup = (Resolve-Path "installer/MPC-BE.$Version.arm64.exe").Path
$inno = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{FE09AF6D-78B2-4093-B012-FCDAF78693CE}_is1'
$legacy = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{3C9B7952-98AC-4240-B0F1-825776ECC782}'
$defaultFolder = Join-Path $env:ProgramFiles 'MPC-BE'
$commonPrograms = [Environment]::GetFolderPath('CommonPrograms')
$flags = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /LANG=en'

function Invoke-Setup([string]$path, [string]$arguments) {
    $p = Start-Process $path -ArgumentList $arguments -PassThru -Wait
    if ($p.ExitCode) { throw "$path returned $($p.ExitCode)" }
}

function Assert-Installation([string]$folder) {
    $app = Get-ItemProperty -LiteralPath $inno
    $player = Join-Path $folder 'mpc-be64.exe'
    $shortcut = Join-Path $commonPrograms "$($app.'Inno Setup: Icon Group')\MPC-BE arm64.lnk"
    $info = (Get-Item $player).VersionInfo
    if ($app.DisplayName -cne "MPC-BE arm64 $Version" -or $app.DisplayVersion -ne $Version -or
        $info.FileVersionRaw -ne [version]"$Version.0" -or $app.InstallLocation.TrimEnd('\') -ne $folder) {
        throw "Incorrect Installed apps metadata: $($app | Out-String)"
    }
    $appPath = (Get-Item 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\mpc-be64.exe').GetValue('')
    $target = (New-Object -ComObject WScript.Shell).CreateShortcut($shortcut).TargetPath
    if ($appPath -ne $player -or (Get-ItemPropertyValue 'HKLM:\SOFTWARE\MPC-BE' ExePath) -ne $player -or
        $target -ne $player -or !(Test-Path $shortcut)) { throw 'Upstream registry paths or shortcut mismatch' }
    $entries = @(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' | Where-Object DisplayName -like 'MPC-BE*')
    if ($entries.Count -ne 1 -or (Test-Path $legacy)) { throw "Duplicate registration: $($entries.DisplayName)" }
    Write-Host "$($app.DisplayName) is the sole product, installed at $player."
}

function Uninstall-Player {
    $app = Get-ItemProperty -LiteralPath $inno
    $player = Join-Path $app.InstallLocation 'mpc-be64.exe'
    Invoke-Setup ($app.UninstallString.Trim('"')) "$flags /LOG=uninstall.log"
    if ((Test-Path $inno) -or (Test-Path $player)) { throw 'Uninstaller left the product or its executable' }
}

# Open the same UI a user gets by double-clicking. No silent or language switches.
python ./contrib/arm64/test-wizard.py $setup
if ($LASTEXITCODE) { throw 'Interactive setup test failed' }
Assert-Installation $defaultFolder
Uninstall-Player

# Recreate both entries from the reported machine, including a non-default upstream directory.
$fixtures = Join-Path $env:RUNNER_TEMP 'setup-fixtures'
New-Item $fixtures -ItemType Directory -Force | Out-Null
$zip = Join-Path $fixtures 'upstream.zip'
Invoke-WebRequest 'https://github.com/Aleksoid1978/MPC-BE/releases/download/1.9.0/MPC-BE.1.9.0.x64-installer.zip' -OutFile $zip
if ((Get-FileHash $zip).Hash -ne '57ed059f3602c281fae2092349f7dc5bda40bdbba287cd05365fad851a7d7db0') { throw 'Unexpected upstream 1.9.0 installer' }
Expand-Archive $zip $fixtures
$folder = Join-Path $env:SystemDrive 'Custom Apps\MPC-BE'
Invoke-Setup (Get-ChildItem $fixtures -Recurse -Filter '*.exe' | Select-Object -First 1).FullName "$flags /DIR=`"$folder`" /LOG=upstream.log"
$before = Get-ItemProperty -LiteralPath $inno
if ($before.DisplayName -ne 'MPC-BE x64 1.9.0') { throw 'Original upstream registration missing' }
$msi = (Resolve-Path 'legacy/*.msi').Path
if ((Get-FileHash $msi).Hash -ne 'cebbae9b59c6cedeed6d2f7878af048fe40d17e1272e7bcd50f9217faf43ebde') { throw 'Unexpected legacy MSI fixture' }
Invoke-Setup msiexec.exe "/i `"$msi`" /qn /norestart"
if (!(Test-Path $legacy)) { throw 'Legacy MSI registration missing' }
$settings = 'HKCU:\Software\MPC-BE\Settings'
New-Item $settings -Force | Out-Null
Set-ItemProperty $settings Volume 67
$ini = Join-Path $folder 'mpc-be64.ini'
[IO.File]::WriteAllText($ini, "[Settings]`r`nVolume=67`r`n", [Text.Encoding]::Unicode)
Invoke-Setup $setup "$flags /COMPONENTS=main,mpciconlib,mpcresources,mpcbeshellext /LOG=upgrade.log"
Assert-Installation $folder
if ((Get-Content $ini -Raw) -notmatch 'Volume=67' -or (Get-ItemPropertyValue $settings Volume) -ne 67) { throw 'Settings did not survive upgrade' }
if ((Test-Path "$env:ProgramFiles\MPC-BE ARM64\mpc-be-arm64.exe") -or (Test-Path "$commonPrograms\MPC-BE (ARM64).lnk") -or
    (Test-Path "$commonPrograms\$($before.'Inno Setup: Icon Group')\MPC-BE x64.lnk")) { throw 'Obsolete player or shortcut remains' }
$com = Get-Item 'Registry::HKEY_CLASSES_ROOT\CLSID\{A2CF4243-6525-4764-B3F5-2FCDE2F47989}\InprocServer32'
if ($com.GetValue('') -ne "$folder\MPCBEShellExt64.dll") { throw 'Shell extension registration mismatch' }
Write-Host 'Verified upgrade from official x64 1.9.0 and published ARM64 MSI, including shared settings and custom directory.'
& ./contrib/arm64/test-playback.ps1 -PlayerDirectory $folder -PlayerName mpc-be64.exe
Remove-Item -LiteralPath $ini
Uninstall-Player
