$ErrorActionPreference='Stop'
$repoRoot=Split-Path -Parent $PSScriptRoot
$pidFile=Join-Path $repoRoot '.local\server.pid'
if(-not(Test-Path -LiteralPath $pidFile)){Write-Output '没有本启动器记录的运行实例。';exit 0}
$serviceId=[int](Get-Content -LiteralPath $pidFile)
$process=Get-Process -Id $serviceId -ErrorAction SilentlyContinue
$expected=[IO.Path]::GetFullPath((Join-Path $repoRoot 'target\release\bin\main.exe'))
if($process){if($process.Path -ne $expected){throw '进程路径与本工程不符，未停止任何进程。'};Stop-Process -Id $serviceId}
Remove-Item -LiteralPath $pidFile
Write-Output '汇率宝已停止，缓存和设置已保留。'
