param(
    [string]$WorkDir = 'C:\ProgramData\InfinityUpdater',
    [ValidateSet('2022','2026','All')]
    [string]$Year = 'All',
    [ValidateSet('Community','Professional','Enterprise','BuildTools')]
    [string]$Edition = 'Community',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$mainScript = Join-Path $PSScriptRoot 'atualizar-softwares.ps1'
if (-not (Test-Path -LiteralPath $mainScript)) {
    Write-Error "Script principal nao encontrado: $mainScript"
    exit 1
}

& $mainScript -Target VisualStudio -WorkDir $WorkDir -Year $Year -Edition $Edition -Force:$Force
exit $LASTEXITCODE
