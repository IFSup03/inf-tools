param(
    [string]$WorkDir = 'C:\ProgramData\InfinityUpdater',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$mainScript = Join-Path $PSScriptRoot 'atualizar-softwares.ps1'
if (-not (Test-Path -LiteralPath $mainScript)) {
    Write-Error "Script principal nao encontrado: $mainScript"
    exit 1
}

& $mainScript -Target PowerBI -WorkDir $WorkDir -Force:$Force
exit $LASTEXITCODE
