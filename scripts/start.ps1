param([switch]$Demo,[switch]$NoBrowser)
. "$PSScriptRoot\env.ps1"
try {
    $running=Invoke-RestMethod -Uri 'http://127.0.0.1:18627/api/state' -TimeoutSec 2
    if($running.engine -eq 'Cangjie'){
        if($running.demo -ne [bool]$Demo){throw '已有另一模式运行，请先使用stop.ps1停止，再启动所需模式。'}
        if(-not $NoBrowser){Start-Process 'http://127.0.0.1:18627'}
        Write-Output '汇率宝已在运行：http://127.0.0.1:18627'
        exit 0
    }
} catch {
    if($_.Exception.Message -like '*另一模式*'){throw}
}
cjpm build
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
$launch=@{FilePath=(Join-Path $repoRoot 'target\release\bin\main.exe');WorkingDirectory=$repoRoot;WindowStyle='Hidden';PassThru=$true}
if(-not(Test-Path -LiteralPath (Join-Path $repoRoot '.local'))){New-Item -ItemType Directory -Path (Join-Path $repoRoot '.local') | Out-Null}
$launch.RedirectStandardOutput=Join-Path $repoRoot '.local\server.stdout.log'
$launch.RedirectStandardError=Join-Path $repoRoot '.local\server.stderr.log'
if($Demo){$launch.ArgumentList=@('--demo')}
$process=Start-Process @launch
$process.Id | Set-Content -LiteralPath (Join-Path $repoRoot '.local\server.pid')
$ready=$false
for($attempt=0;$attempt -lt 30;$attempt++){
    if($process.HasExited){throw '汇率宝服务未能启动，请检查SDK与stdx版本。'}
    try { $response=Invoke-RestMethod -Uri 'http://127.0.0.1:18627/api/state' -TimeoutSec 1; if($response.engine -eq 'Cangjie'){$ready=$true;break} } catch {}
    Start-Sleep -Milliseconds 200
}
if(-not $ready){throw '启动尚未就绪，请检查本机18627端口。'}
if(-not $NoBrowser){Start-Process 'http://127.0.0.1:18627'}
Write-Output '汇率宝已启动：http://127.0.0.1:18627'
