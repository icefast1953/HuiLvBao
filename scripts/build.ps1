. "$PSScriptRoot\env.ps1"
cjpm build
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
