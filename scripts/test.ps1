. "$PSScriptRoot\env.ps1"
cjpm test
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
