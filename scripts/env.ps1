$ErrorActionPreference='Stop'
$repoRoot=Split-Path -Parent $PSScriptRoot
if(Test-Path -LiteralPath (Join-Path $repoRoot 'local.env.ps1')){ . (Join-Path $repoRoot 'local.env.ps1') }
if(-not $env:CANGJIE_HOME){ $env:CANGJIE_HOME=Join-Path (Split-Path -Parent $repoRoot) 'cangjie-rebuild\nightly\cangjie' }
if(-not $env:STDX_HOME){ $env:STDX_HOME=Join-Path (Split-Path -Parent $repoRoot) 'cangjie-rebuild\stdx-nightly\windows_x86_64_cjnative' }
if(-not(Test-Path -LiteralPath "$env:CANGJIE_HOME\envsetup.ps1")){ throw '请先设置CANGJIE_HOME，指向仓颉SDK目录。' }
. "$env:CANGJIE_HOME\envsetup.ps1"
$env:Path="$env:STDX_HOME\dynamic\stdx;$env:Path"
Set-Location -LiteralPath $repoRoot
