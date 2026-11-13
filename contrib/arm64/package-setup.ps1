$ErrorActionPreference = 'Stop'
$compiler = Join-Path $env:RUNNER_TEMP 'inno-6.7.4'
$bootstrap = "$compiler.exe"
Invoke-WebRequest 'https://github.com/jrsoftware/issrc/releases/download/is-6_7_4/innosetup-6.7.4.exe' -OutFile $bootstrap
if ((Get-FileHash $bootstrap).Hash -ne 'a549929319f9120716677c685535ca4671e4b937b5fdc87e2585f32d8eb30e8c') {
    throw 'Unexpected Inno Setup compiler package digest'
}
$p = Start-Process $bootstrap -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /CURRENTUSER /DIR=`"$compiler`"" -Wait -PassThru
if ($p.ExitCode) { throw "Inno Setup compiler installation failed ($($p.ExitCode))" }
# Use the same installed executable name as upstream for existing associations, INIs and pinned shortcuts.
Copy-Item _bin/mpc-be_ARM64/mpc-be-arm64.exe _bin/mpc-be_ARM64/mpc-be64.exe
& .\update_revision.cmd
if ($LASTEXITCODE) { exit $LASTEXITCODE }
New-Item installer -ItemType Directory -Force | Out-Null
& "$compiler/ISCC.exe" /DArm64Build "/O$PWD/installer" distrib/mpc-be_setup.iss
if ($LASTEXITCODE) { exit $LASTEXITCODE }
