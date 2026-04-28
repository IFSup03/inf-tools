<#
.SYNOPSIS
    Remove aplicativos pre-instalados (bloatware) do Windows e bloqueia reinstalacao automatica.

.DESCRIPTION
    Script de limpeza que remove apps Appx e Win32 indesejados do Windows 10/11/Server,
    com suporte a:
      - Modo interativo (menu) e nao-interativo (via switches)
      - Auto-elevacao compativel com `irm | iex` e arquivo local
      - Lista de apps protegidos (impede remocao acidental de componentes do sistema)
      - Bloqueio amplo de reinstalacao via Registry (HKLM + HKCU + ContentDeliveryManager)
      - Deteccao de edicao Windows (Home/Pro/Enterprise/Server) e versao (10/11)
      - Avisos quando GPO nao se aplica (Home Edition)
      - Console UTF-8/VT com fallback ASCII
      - Log estruturado via -LogPath (Start-Transcript)

.PARAMETER Apps
    Lista de categorias a remover. Aceita:
    Xbox, Outlook, OneDrive, Padrao, Cortana, Midia, Copilot, Office,
    Outros, StickyNotes, Multimidia, Consumer, Teams, Clipchamp,
    News, Family

.PARAMETER Tudo
    Remove todas as categorias listadas no catalogo.

.PARAMETER Silent
    Modo nao-interativo: sem prompts, sem ESPERAS, sem menu.

.PARAMETER LogPath
    Caminho do arquivo de log (transcript). Em -Silent grava
    automaticamente em %TEMP%\remove-apps_<timestamp>.log se omitido.

.PARAMETER NoBlockReinstall
    Pula a etapa de bloqueio de reinstalacao via Registry. Util quando
    voce quer apenas remover, sem aplicar politica.

.PARAMETER SkipProtectedCheck
    [PERIGOSO] Pula a verificacao de apps protegidos. Permite remover
    componentes do sistema. Use somente se souber o que esta fazendo.

.EXAMPLE
    .\remove-apps.ps1
    Abre o menu interativo.

.EXAMPLE
    .\remove-apps.ps1 -Tudo -Silent -LogPath "C:\Logs\remove.log"
    Remove tudo em modo automatico, gravando log.

.EXAMPLE
    .\remove-apps.ps1 -Apps Xbox,Cortana,Consumer -Silent
    Remove Xbox, Cortana e apps consumer (Spotify, TikTok, etc) sem prompts.

.EXAMPLE
    .\remove-apps.ps1 -Tudo -WhatIf
    Simula remocao de tudo sem aplicar nada.

.NOTES
    Autor       : Victor Hugo Gomides (refatorado em 2026)
    Versao      : 2.0.2
    Compatibilidade : Windows 10/11, Server 2016+, PowerShell 5.1+
    RequerAdmin : sim
#>
[CmdletBinding(DefaultParameterSetName='Interactive', SupportsShouldProcess=$true)]
param(
    [Parameter(ParameterSetName='Apps')]
    [ValidateSet('Xbox','Outlook','OneDrive','Padrao','Cortana','Midia','Copilot',
                 'Office','Outros','StickyNotes','Multimidia','Consumer','Teams',
                 'Clipchamp','News','Family')]
    [string[]]$Apps,

    [Parameter(ParameterSetName='Tudo')]
    [switch]$Tudo,

    [switch]$Silent,
    [string]$LogPath,
    [switch]$NoBlockReinstall,
    [switch]$SkipProtectedCheck
)

$ErrorActionPreference = "Continue"

# ----------------------------------------------------------
# Versao e historico
# ----------------------------------------------------------
$SCRIPT_VERSION = "2.0.2"
$SCRIPT_DATA    = "28/04/2026"
$CHANGELOG = @(
    [PSCustomObject]@{ Versao = "2.0.2"; Data = "28/04/2026"; Descricao = "Visual: alinha fluxo de remocao ao padrao do ia-install com resumo unico e categorias mais explicitas" },
    [PSCustomObject]@{ Versao = "2.0.1"; Data = "28/04/2026"; Descricao = "UX: remove simbolos Unicode da interface e pergunta se deseja voltar ao menu apos concluir" },
    [PSCustomObject]@{ Versao = "2.0.1"; Data = "28/04/2026"; Descricao = "Fix: auto-elevacao preserva arrays como -Apps Xbox Cortana em vez de string unica" },
    [PSCustomObject]@{ Versao = "2.0.1"; Data = "28/04/2026"; Descricao = "Fix: escrita de DWORD no Registry usa New-ItemProperty -PropertyType DWord em vez de Set-ItemProperty -Type" },
    [PSCustomObject]@{ Versao = "2.0.1"; Data = "28/04/2026"; Descricao = "Fix: funcao interna Remove-AppPackage renomeada para Invoke-AppPackageRemoval para evitar colisao com cmdlets/modulos externos" },
    [PSCustomObject]@{ Versao = "2.0.1"; Data = "28/04/2026"; Descricao = "Fix: $script:APPS renomeado para $script:AppsCatalog (colisao com parametro -Apps)" },
    [PSCustomObject]@{ Versao = "2.0.1"; Data = "28/04/2026"; Descricao = "Fix: SymShield usa ConvertFromUtf32 (codepoint 0x1F6E1 esta fora do BMP)" },
    [PSCustomObject]@{ Versao = "2.0.0"; Data = "28/04/2026"; Descricao = "Reescrita: param block + CmdletBinding, modo nao-interativo via -Apps/-Tudo/-Silent" },
    [PSCustomObject]@{ Versao = "2.0.0"; Data = "28/04/2026"; Descricao = "Novo: catalogo expandido com apps consumer (Spotify, TikTok, Disney, MSTeams, Clipchamp, etc)" },
    [PSCustomObject]@{ Versao = "2.0.0"; Data = "28/04/2026"; Descricao = "Seguranca: lista de apps protegidos impede remocao acidental de componentes do sistema" },
    [PSCustomObject]@{ Versao = "2.0.0"; Data = "28/04/2026"; Descricao = "Bloqueio: Registry expandido (HKLM + HKCU + 12 chaves de ContentDeliveryManager)" },
    [PSCustomObject]@{ Versao = "2.0.0"; Data = "28/04/2026"; Descricao = "Deteccao: edicao Windows (Home/Pro), versao (10/11), avisos de GPO inaplicavel" },
    [PSCustomObject]@{ Versao = "2.0.0"; Data = "28/04/2026"; Descricao = "Visual: dashboard, simbolos Unicode com fallback ASCII, badges coloridos, tempo total" },
    [PSCustomObject]@{ Versao = "2.0.0"; Data = "28/04/2026"; Descricao = "Fix: auto-elevacao compativel com irm | iex (PSCommandPath/PSScriptRoot vazios)" },
    [PSCustomObject]@{ Versao = "2.0.0"; Data = "28/04/2026"; Descricao = "Fix: log path robusto (cai em %TEMP% se PSScriptRoot vazio)" },
    [PSCustomObject]@{ Versao = "2.0.0"; Data = "28/04/2026"; Descricao = "Fix: OneDrive remove tambem o cliente Win32 (OneDriveSetup.exe /uninstall)" },
    [PSCustomObject]@{ Versao = "2.0.0"; Data = "28/04/2026"; Descricao = "Fix: Copilot tenta winget antes de Remove-AppxPackage (Win11 24H2+)" },
    [PSCustomObject]@{ Versao = "2.0.0"; Data = "28/04/2026"; Descricao = "Quality: SupportsShouldProcess=true permite -WhatIf para simulacao" },
    [PSCustomObject]@{ Versao = "1.1.0"; Data = "07/05/2025"; Descricao = "Versao original (Victor Hugo Gomides): menu numerico + bloqueio basico" },
    [PSCustomObject]@{ Versao = "1.0.0"; Data = "07/05/2025"; Descricao = "Versao inicial" }
)

# ----------------------------------------------------------
# Modo nao-interativo + transcript
# ----------------------------------------------------------
$script:NonInteractive = $Silent.IsPresent -or
                         [Console]::IsInputRedirected -or
                         (-not [Environment]::UserInteractive)

$script:TranscriptStarted = $false
if ($LogPath -or ($Silent -and -not $LogPath)) {
    if (-not $LogPath) {
        $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $LogPath = Join-Path $env:TEMP "remove-apps_$stamp.log"
    }
    try {
        $logDir = Split-Path -Parent $LogPath
        if ($logDir -and -not (Test-Path -LiteralPath $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force -ErrorAction SilentlyContinue | Out-Null
        }
        Start-Transcript -Path $LogPath -Append -ErrorAction Stop | Out-Null
        $script:TranscriptStarted = $true
    } catch { Write-Warning "Nao foi possivel iniciar transcript em $LogPath : $_" }
}

# ----------------------------------------------------------
# CATALOGO DE APPS - cada categoria mapeia para identificadores Appx
# Inclui apps modernos (consumer, MSTeams personal, etc) que o original nao cobria
# ----------------------------------------------------------
$script:AppsCatalog = [ordered]@{
    'Xbox' = [PSCustomObject]@{
        Display = 'Xbox (Game Bar, Console Companion, Identidade, Gaming Overlay)'
        Apps = @(
            'Microsoft.XboxGameOverlay',
            'Microsoft.Xbox.TCUI',
            'Microsoft.XboxGamingOverlay',
            'Microsoft.XboxIdentityProvider',
            'Microsoft.XboxSpeechToTextOverlay',
            'Microsoft.GamingApp',
            'Microsoft.XboxApp'
        )
    }
    'Outlook' = [PSCustomObject]@{
        Display = 'Outlook (versao Microsoft Store, nao corporativo)'
        Apps = @('Microsoft.OutlookForWindows')
    }
    'OneDrive' = [PSCustomObject]@{
        Display = 'OneDrive (sync provider Appx + cliente Win32 OneDriveSetup)'
        Apps = @('Microsoft.OneDriveSync')
        Win32 = $true  # tambem desinstala OneDriveSetup.exe
    }
    'Padrao' = [PSCustomObject]@{
        Display = 'Padrao MS (OneNote, Paint 3D, Skype, Phone, Feedback, Solitaire)'
        Apps = @(
            'Microsoft.Office.OneNote',
            'Microsoft.MSPaint',
            'Microsoft.SkypeApp',
            'Microsoft.YourPhone',
            'Microsoft.MixedReality.Portal',
            'Microsoft.WindowsFeedbackHub',
            'Microsoft.MicrosoftSolitaireCollection',
            'Microsoft.GetStarted'
        )
    }
    'Cortana' = [PSCustomObject]@{
        Display = 'Cortana (assistente virtual)'
        Apps = @('Microsoft.549981C3F5F10')
    }
    'Midia' = [PSCustomObject]@{
        Display = 'Midia (Fotos, Filmes, Mapas, Clima)'
        Apps = @(
            'Microsoft.ZuneVideo',
            'Microsoft.Windows.Photos',
            'Microsoft.WindowsMaps',
            'Microsoft.BingWeather'
        )
    }
    'Copilot' = [PSCustomObject]@{
        Display = 'Copilot (Win11 24H2+ usa winget, anteriores usa Appx)'
        Apps = @('Microsoft.Copilot','Microsoft.Windows.Ai.Copilot.Provider')
        Winget = 'Microsoft.Copilot'
    }
    'Office' = [PSCustomObject]@{
        Display = 'Email/Hub Office (Mail, Calendar, MicrosoftOfficeHub)'
        Apps = @(
            'microsoft.windowscommunicationsapps',
            'Microsoft.MicrosoftOfficeHub',
            'Microsoft.Office.Sway'
        )
    }
    'Outros' = [PSCustomObject]@{
        Display = 'Outros (Ajuda, Camera, Alarmes, 3D Viewer, Voice Recorder)'
        Apps = @(
            'Microsoft.GetHelp',
            'Microsoft.WindowsCamera',
            'Microsoft.WindowsAlarms',
            'Microsoft.Microsoft3DViewer',
            'Microsoft.WindowsSoundRecorder',
            'Microsoft.MicrosoftPowerBIForWindows',
            'MicrosoftCorporationII.QuickAssist'
        )
    }
    'StickyNotes' = [PSCustomObject]@{
        Display = 'Sticky Notes (Notas Autoadesivas)'
        Apps = @('Microsoft.MicrosoftStickyNotes')
    }
    'Multimidia' = [PSCustomObject]@{
        Display = 'Reprodutor multimidia (Zune Music, codecs Web/VP9)'
        Apps = @(
            'Microsoft.ZuneMusic',
            'Microsoft.WebMediaExtensions',
            'Microsoft.VP9VideoExtensions'
        )
    }
    'Consumer' = [PSCustomObject]@{
        Display = 'Apps consumer (Spotify, TikTok, Disney, Facebook, Instagram, LinkedIn)'
        Apps = @(
            'SpotifyAB.SpotifyMusic',
            'BytedancePte.Ltd.TikTok',
            'Disney.37853FC22B2CE',
            'Facebook.Facebook',
            'Facebook.Instagram',
            'Microsoft.LinkedIn',
            '7EE7776C.LinkedInforWindows',
            'Netflix.Netflix',
            'Amazon.com.Amazon',
            'PandoraMediaInc.29680B314EFC2',
            'Microsoft.News',
            'Microsoft.BingNews'
        )
    }
    'Teams' = [PSCustomObject]@{
        Display = 'Microsoft Teams Personal/Consumer (NAO corporativo)'
        Apps = @(
            'MicrosoftTeams',
            'MSTeams'
        )
    }
    'Clipchamp' = [PSCustomObject]@{
        Display = 'Clipchamp (editor de video preinstalado)'
        Apps = @(
            'Clipchamp.Clipchamp',
            'Microsoft.Clipchamp'
        )
    }
    'News' = [PSCustomObject]@{
        Display = 'News (Bing News + Microsoft News)'
        Apps = @(
            'Microsoft.BingNews',
            'Microsoft.News'
        )
    }
    'Family' = [PSCustomObject]@{
        Display = 'Family + PowerAutomate (apps preinstalados desnecessarios)'
        Apps = @(
            'MicrosoftCorporationII.MicrosoftFamily',
            'Microsoft.PowerAutomateDesktop'
        )
    }
}

# ----------------------------------------------------------
# APPS PROTEGIDOS - jamais devem ser removidos (quebram o sistema)
# Verificacao executada antes de cada remocao a menos que -SkipProtectedCheck
# ----------------------------------------------------------
$script:PROTECTED_APPS = @(
    'Microsoft.WindowsStore',
    'Microsoft.StorePurchaseApp',
    'Microsoft.Windows.ShellExperienceHost',
    'Microsoft.Windows.StartMenuExperienceHost',
    'Microsoft.Windows.Cortana',  # parte do shell em algumas versoes
    'Microsoft.Windows.SecureAssessmentBrowser',
    'Microsoft.Windows.NarratorQuickStart',
    'Microsoft.Windows.PeopleExperienceHost',
    'Microsoft.WindowsCalculator',  # nao quebra mas e util
    'Microsoft.UI.Xaml.*',
    'Microsoft.VCLibs.*',
    'Microsoft.NET.Native.*',
    'Microsoft.NET.Native.Framework.*',
    'Microsoft.NET.Native.Runtime.*',
    'Microsoft.Services.Store.Engagement',
    'Microsoft.AAD.BrokerPlugin',
    'Microsoft.AccountsControl',
    'Microsoft.LockApp',
    'Microsoft.MicrosoftEdge*',
    'Microsoft.WebpImageExtension',
    'Microsoft.HEIFImageExtension',
    'Microsoft.Wallet',
    'Windows.PrintDialog',
    'Windows.CBSPreview',
    'Windows.MiracastView'
)

# ----------------------------------------------------------
# Encoding e VT100
# ----------------------------------------------------------
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    [Console]::InputEncoding  = [System.Text.Encoding]::UTF8
    $OutputEncoding           = [System.Text.Encoding]::UTF8
} catch { }

try {
    $sig = @"
        [DllImport("kernel32.dll", SetLastError=true)]
        public static extern IntPtr GetStdHandle(int nStdHandle);
        [DllImport("kernel32.dll", SetLastError=true)]
        public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
        [DllImport("kernel32.dll", SetLastError=true)]
        public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
"@
    $k32    = Add-Type -MemberDefinition $sig -Name "K32VT" -Namespace "Win32" -PassThru -ErrorAction SilentlyContinue
    $handle = [Win32.K32VT]::GetStdHandle(-11)
    $mode   = 0
    [Win32.K32VT]::GetConsoleMode($handle, [ref]$mode) | Out-Null
    [Win32.K32VT]::SetConsoleMode($handle, ($mode -bor 0x0004)) | Out-Null
} catch { }

# ----------------------------------------------------------
# PRE-FLIGHT: detecta capacidades + edicao Windows
# ----------------------------------------------------------
$script:Compat = [PSCustomObject]@{
    PSMajor       = $PSVersionTable.PSVersion.Major
    PSEdition     = if ($PSVersionTable.PSEdition) { $PSVersionTable.PSEdition } else { 'Desktop' }
    ConsoleUTF8   = $false
    ConsoleVT     = $false
    ConsoleRedir  = $false
    UnicodeOk     = $false
    WindowsVer    = $null   # 10, 11, ou 'Server'
    Edition       = $null   # Home, Pro, Enterprise, Education, Server
    BuildNumber   = $null
    IsHome        = $false
    GpoApplica    = $false  # se DisableWindowsConsumerFeatures aplica nesta edicao
    HasWinget     = $false
    OsCaption     = $null
}

try { $script:Compat.ConsoleRedir = ([Console]::IsOutputRedirected -or [Console]::IsErrorRedirected) } catch { }
try { $script:Compat.ConsoleUTF8  = ([Console]::OutputEncoding.WebName -match 'utf-?8') } catch { }
$script:Compat.UnicodeOk = ($script:Compat.ConsoleUTF8 -and (-not $script:Compat.ConsoleRedir))

try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    $script:Compat.OsCaption   = $os.Caption
    $script:Compat.BuildNumber = [int]$os.BuildNumber
    # Win11 = build 22000+
    if ($os.ProductType -ne 1) {
        $script:Compat.WindowsVer = 'Server'
    } elseif ($script:Compat.BuildNumber -ge 22000) {
        $script:Compat.WindowsVer = '11'
    } else {
        $script:Compat.WindowsVer = '10'
    }
    # Edicao via SkuNumber + Caption
    if ($os.Caption -match 'Home')              { $script:Compat.Edition = 'Home'; $script:Compat.IsHome = $true }
    elseif ($os.Caption -match 'Pro')           { $script:Compat.Edition = 'Pro' }
    elseif ($os.Caption -match 'Enterprise')    { $script:Compat.Edition = 'Enterprise' }
    elseif ($os.Caption -match 'Education')     { $script:Compat.Edition = 'Education' }
    elseif ($os.Caption -match 'Server')        { $script:Compat.Edition = 'Server' }
    else                                        { $script:Compat.Edition = 'Desconhecido' }
} catch { }

# DisableWindowsConsumerFeatures so funciona em Pro/Enterprise/Education/Server
$script:Compat.GpoApplica = ($script:Compat.Edition -in @('Pro','Enterprise','Education','Server'))

try { $null = & winget --version 2>&1; $script:Compat.HasWinget = ($LASTEXITCODE -eq 0) } catch { }

# ----------------------------------------------------------
# Simbolos ASCII - evita caracteres que falham em consoles/fontes diferentes
# ----------------------------------------------------------
$script:SymOk     = 'OK'
$script:SymFail   = 'ERRO'
$script:SymWarn   = 'AVISO'
$script:SymStep   = '>'
$script:SymInfo   = 'INFO'
$script:SymBullet = '-'
$script:SymTrash  = 'X'
$script:SymShield = 'PROT'
$script:BoxTL = '+'; $script:BoxTR = '+'; $script:BoxBL = '+'; $script:BoxBR = '+'
$script:BoxH = '-';  $script:BoxV = '|'
$script:SpinFrames = @('|','/','-','\')

# ----------------------------------------------------------
# State global
# ----------------------------------------------------------
$script:RemoveResults  = @()
$script:ScriptStartTime = $null
$script:ForceMenu = $false

# ----------------------------------------------------------
# UI helpers
# ----------------------------------------------------------
function Write-Step  { param($msg) Write-Host ("  {0} {1}" -f $script:SymStep, $msg) -ForegroundColor Cyan }
function Write-Ok    { param($msg) Write-Host ("  {0} {1}" -f $script:SymOk,   $msg) -ForegroundColor Green }
function Write-Warn  { param($msg) Write-Host ("  {0} {1}" -f $script:SymWarn, $msg) -ForegroundColor Yellow }
function Write-Fail  { param($msg) Write-Host ("  {0} {1}" -f $script:SymFail, $msg) -ForegroundColor Red }
function Write-Info  { param($msg) Write-Host ("  {0} {1}" -f $script:SymInfo, $msg) -ForegroundColor Gray }

function Write-Banner {
    try { Clear-Host } catch { }
    $hLine = ([string]$script:BoxH) * 61
    $empty = ' ' * 61
    Write-Host ""
    Write-Host ("  $($script:BoxTL)$hLine$($script:BoxTR)") -ForegroundColor Cyan
    Write-Host ("  $($script:BoxV)$empty$($script:BoxV)") -ForegroundColor Cyan
    Write-Host ("  $($script:BoxV)     R E M O V E - A P P S                                   $($script:BoxV)") -ForegroundColor White
    Write-Host ("  $($script:BoxV)$empty$($script:BoxV)") -ForegroundColor Cyan
    Write-Host ("  $($script:BoxV)     Limpeza de bloatware do Windows                         $($script:BoxV)") -ForegroundColor DarkCyan
    Write-Host ("  $($script:BoxV)$empty$($script:BoxV)") -ForegroundColor Cyan
    Write-Host ("  $($script:BoxV)     v{0,-6}                                                  $($script:BoxV)" -f $SCRIPT_VERSION) -ForegroundColor DarkGray
    Write-Host ("  $($script:BoxV)$empty$($script:BoxV)") -ForegroundColor Cyan
    Write-Host ("  $($script:BoxBL)$hLine$($script:BoxBR)") -ForegroundColor Cyan
    Write-Host ""

    # Info do sistema detectado
    if ($script:Compat.OsCaption) {
        Write-Host ("  Sistema: {0} (build {1})" -f $script:Compat.OsCaption, $script:Compat.BuildNumber) -ForegroundColor DarkGray
    }
    if ($script:Compat.IsHome) {
        Write-Host "  $($script:SymWarn) Edicao Home detectada: bloqueio de reinstalacao via GPO sera limitado." -ForegroundColor Yellow
    }
    Write-Host ""
}

function Write-Phase {
    param([string]$Title)
    $hLine = ([string]$script:BoxH) * 59
    $titleLine = $Title.PadRight(58)
    if ($titleLine.Length -gt 58) { $titleLine = $titleLine.Substring(0,58) }
    Write-Host ""
    Write-Host ("  $($script:BoxTL)$hLine$($script:BoxTR)") -ForegroundColor DarkCyan
    Write-Host ("  $($script:BoxV) {0} $($script:BoxV)" -f $titleLine) -ForegroundColor Cyan
    Write-Host ("  $($script:BoxBL)$hLine$($script:BoxBR)") -ForegroundColor DarkCyan
}

function Wait-Readable {
    param([int]$Seconds = 2)
    if ($script:NonInteractive) { return }
    Start-Sleep -Seconds $Seconds
}

function Confirm-Tecla {
    param([string]$Mensagem)
    if ($script:NonInteractive) {
        Write-Verbose "[NonInteractive] Auto-confirmando: $Mensagem"
        return $true
    }
    Write-Host "  $Mensagem [ENTER = sim | ESC = nao] " -ForegroundColor White -NoNewline
    while ($true) {
        $key = [Console]::ReadKey($true)
        if ($key.Key -eq 'Enter') { Write-Host "Sim" -ForegroundColor Green; return $true }
        if ($key.Key -eq 'Escape') { Write-Host "Nao" -ForegroundColor Gray; return $false }
    }
}

function Confirm-VoltarMenu {
    if ($script:NonInteractive) { return $false }

    Write-Host ""
    Write-Host "  O que deseja fazer agora? [ENTER = voltar ao menu | ESC = sair] " -ForegroundColor White -NoNewline

    while ($true) {
        $key = [Console]::ReadKey($true)
        if ($key.Key -eq 'Enter') { Write-Host "Voltar ao menu" -ForegroundColor Cyan; return $true }
        if ($key.Key -eq 'Escape') { Write-Host "Sair" -ForegroundColor Yellow; return $false }
    }
}

function Add-RemoveResult {
    param(
        [string]$Categoria,
        [string]$App,
        [ValidateSet('REMOVIDO','NAO_ENCONTRADO','PROTEGIDO','FALHOU','SIMULADO')]
        [string]$Status,
        [string]$Obs = ''
    )
    $script:RemoveResults += [PSCustomObject]@{
        Categoria = $Categoria
        App       = $App
        Status    = $Status
        Obs       = $Obs
    }
}

function Show-Summary {
    $elapsedSpan = if ($script:ScriptStartTime) { (Get-Date) - $script:ScriptStartTime } else { [TimeSpan]::Zero }
    $elapsedStr = if ($elapsedSpan.TotalMinutes -ge 1) {
        "{0}m {1}s" -f [int]$elapsedSpan.TotalMinutes, $elapsedSpan.Seconds
    } else {
        "{0}s" -f [int]$elapsedSpan.TotalSeconds
    }

    $rem  = @($script:RemoveResults | Where-Object { $_.Status -eq 'REMOVIDO' }).Count
    $nf   = @($script:RemoveResults | Where-Object { $_.Status -eq 'NAO_ENCONTRADO' }).Count
    $prot = @($script:RemoveResults | Where-Object { $_.Status -eq 'PROTEGIDO' }).Count
    $fail = @($script:RemoveResults | Where-Object { $_.Status -eq 'FALHOU' }).Count
    $sim  = @($script:RemoveResults | Where-Object { $_.Status -eq 'SIMULADO' }).Count
    $tot  = @($script:RemoveResults).Count

    $headerColor = if ($fail -gt 0) { 'Red' } elseif ($rem -gt 0 -or $sim -gt 0) { 'Green' } else { 'Yellow' }
    $headerLabel = if ($fail -gt 0) { 'CONCLUIDO COM FALHAS' }
                   elseif ($sim -gt 0) { 'SIMULACAO COMPLETA (-WhatIf)' }
                   elseif ($rem -gt 0) { 'LIMPEZA CONCLUIDA' }
                   else { 'NADA REMOVIDO' }

    $hLine = ([string]$script:BoxH) * 61
    Write-Host ""
    Write-Host ("  $($script:BoxTL)$hLine$($script:BoxTR)") -ForegroundColor Cyan
    $linha1 = "  RESUMO  (tempo total: $elapsedStr)".PadRight(61)
    Write-Host ("  $($script:BoxV)$linha1$($script:BoxV)") -ForegroundColor White
    $linha2 = "  $($script:SymBullet) $headerLabel  ($rem removidos / $nf nao encontrados / $fail falhas / $prot protegidos)".PadRight(61)
    if ($linha2.Length -gt 61) { $linha2 = $linha2.Substring(0, 61) }
    Write-Host ("  $($script:BoxV)$linha2$($script:BoxV)") -ForegroundColor $headerColor
    Write-Host ("  $($script:BoxBL)$hLine$($script:BoxBR)") -ForegroundColor Cyan

    if ($script:RemoveResults.Count -eq 0) {
        Write-Host "  (Nenhum app processado)" -ForegroundColor DarkGray
        return
    }

    Write-Host ""
    Write-Host ("    {0,-12} {1,-32} {2}" -f 'CATEGORIA','APP','STATUS') -ForegroundColor DarkGray
    $div = ([string]$script:BoxH) * 60
    Write-Host "    $div" -ForegroundColor DarkGray

    foreach ($r in $script:RemoveResults) {
        $badge = ''; $cor = 'White'
        switch ($r.Status) {
            'REMOVIDO'       { $badge = "[$($script:SymOk) REMOVIDO]";       $cor = 'Green' }
            'SIMULADO'       { $badge = "[$($script:SymInfo) SIMULADO]";     $cor = 'Cyan' }
            'NAO_ENCONTRADO' { $badge = "[$($script:SymBullet) NAO ENCONTRADO]"; $cor = 'DarkGray' }
            'PROTEGIDO'      { $badge = "[$($script:SymShield) PROTEGIDO]";  $cor = 'Yellow' }
            'FALHOU'         { $badge = "[$($script:SymFail) FALHOU]";       $cor = 'Red' }
        }
        $cat = if ($r.Categoria.Length -gt 12) { $r.Categoria.Substring(0,12) } else { $r.Categoria }
        $app = if ($r.App.Length -gt 32) { $r.App.Substring(0,29) + '...' } else { $r.App }
        Write-Host ("    {0,-12} {1,-32} " -f $cat, $app) -ForegroundColor White -NoNewline
        Write-Host $badge -ForegroundColor $cor -NoNewline
        if ($r.Obs) { Write-Host (" $($r.Obs)") -ForegroundColor DarkGray } else { Write-Host '' }
    }
    Write-Host ""
}

# ----------------------------------------------------------
# Auto-elevacao (compativel com irm | iex e arquivo local)
# ----------------------------------------------------------
function Test-IsAdmin {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

<#
.SYNOPSIS
    Reexecuta o script com privilegios elevados, preservando o visual moderno
    (Windows Terminal preto) sempre que possivel.
.DESCRIPTION
    Estrategia em ordem de preferencia:
      1. wt.exe (Windows Terminal) com -Verb RunAs   -> mantem tela preta moderna
      2. pwsh.exe (PowerShell 7+) com BG forcado     -> tema escuro
      3. powershell.exe legacy com BG forcado        -> conhost com fundo preto (em vez do azul)
    Em modo Silent ignora wt.exe (precisa de exit code limpo) e usa powershell.exe direto.
#>
function Request-Elevation {
    Write-Host "  $($script:SymWarn) Este script requer privilegios administrativos." -ForegroundColor Yellow
    Write-Host "  Solicitando elevacao via UAC..." -ForegroundColor Yellow

    # Resolve caminho do script
    $cmdPath = $PSCommandPath
    if (-not $cmdPath) { $cmdPath = $MyInvocation.PSCommandPath }
    if (-not $cmdPath) { $cmdPath = $MyInvocation.MyCommand.Path }

    if (-not ($cmdPath -and (Test-Path -LiteralPath $cmdPath))) {
        # Modo irm | iex: nao tem como relancar
        Write-Host "  $($script:SymFail) Detectado modo irm | iex (sem arquivo local)." -ForegroundColor Red
        Write-Host "  Por favor, abra um PowerShell como Administrador e execute:" -ForegroundColor Yellow
        Write-Host "    irm <URL-DO-SCRIPT> | iex" -ForegroundColor White
        exit 1
    }

    # Constroi lista de parametros para repassar
    $paramArgs = @()
    foreach ($p in $PSBoundParameters.GetEnumerator()) {
        if ($p.Value -is [System.Management.Automation.SwitchParameter] -and $p.Value) {
            $paramArgs += "-$($p.Key)"
        } elseif ($p.Value -is [array]) {
            $paramArgs += "-$($p.Key)"
            foreach ($item in $p.Value) {
                $paramArgs += "`"$item`""
            }
        } else {
            $paramArgs += "-$($p.Key)"
            $paramArgs += "`"$($p.Value)`""
        }
    }

    # Detecta shells disponiveis (preferencia: pwsh > powershell)
    $shellPath = 'powershell.exe'
    try {
        $pwsh = Get-Command pwsh.exe -ErrorAction Stop
        if ($pwsh) { $shellPath = $pwsh.Source }
    } catch { }

    # Detecta Windows Terminal (wt.exe) - mantem tela preta moderna
    $wtPath = $null
    if (-not $Silent) {
        try {
            $wt = Get-Command wt.exe -ErrorAction Stop
            if ($wt) { $wtPath = $wt.Source }
        } catch { }
        # Em algumas instalacoes wt.exe so esta no LocalAppData
        if (-not $wtPath) {
            $candidato = "$env:LOCALAPPDATA\Microsoft\WindowsApps\wt.exe"
            if (Test-Path -LiteralPath $candidato) { $wtPath = $candidato }
        }
    }

    try {
        if ($wtPath) {
            # PREFERENCIA: Windows Terminal abre janela preta moderna
            # wt.exe -w -1 forca nova janela (necessario quando elevado a partir de sessao nao-elevada)
            $wtArgs = @(
                '-w','-1',
                'new-tab',
                '--title','remove-apps',
                '--suppressApplicationTitle',
                '--',
                $shellPath,
                '-NoProfile',
                '-ExecutionPolicy','Bypass',
                '-File',"`"$cmdPath`""
            ) + $paramArgs
            Write-Host "  $($script:SymInfo) Abrindo Windows Terminal elevado..." -ForegroundColor Gray
            $proc = Start-Process -FilePath $wtPath -Verb RunAs -ArgumentList $wtArgs -PassThru -ErrorAction Stop
            $proc.WaitForExit()
            exit $proc.ExitCode
        } else {
            # FALLBACK: powershell/pwsh com BackgroundColor=Black forcado via -Command
            # Resultado: conhost legacy mas com fundo preto (em vez do azul padrao)
            $paramStr = $paramArgs -join ' '
            $cmdString = @"
try {
  `$Host.UI.RawUI.BackgroundColor = 'Black'
  `$Host.UI.RawUI.ForegroundColor = 'White'
  Clear-Host
} catch {}
& '$cmdPath' $paramStr
"@
            $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-Command', $cmdString)
            Write-Host "  $($script:SymInfo) Abrindo console elevado (fundo preto forcado)..." -ForegroundColor Gray
            $proc = Start-Process -FilePath $shellPath -Verb RunAs -ArgumentList $argList -PassThru -ErrorAction Stop
            $proc.WaitForExit()
            exit $proc.ExitCode
        }
    } catch {
        Write-Host "  $($script:SymFail) Elevacao cancelada: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

if (-not (Test-IsAdmin)) {
    Request-Elevation
}

# ----------------------------------------------------------
# Helpers de remocao
# ----------------------------------------------------------

<#
.SYNOPSIS
    Verifica se um nome de app esta na lista de protegidos.
.OUTPUTS
    [bool] $true se for protegido (NAO deve ser removido), $false caso contrario.
#>
function Test-IsProtectedApp {
    param([string]$AppName)
    foreach ($pattern in $script:PROTECTED_APPS) {
        if ($AppName -like $pattern) { return $true }
    }
    return $false
}

<#
.SYNOPSIS
    Tenta remover um app via Appx (provisioned + installed) e Win32/Winget quando aplicavel.
.PARAMETER Categoria
    Nome da categoria (Xbox, Cortana, etc) para o relatorio.
.PARAMETER App
    Nome do pacote Appx (sem versao/arch). Ex: "Microsoft.XboxApp"
.PARAMETER ProvisionedList
    Lista pre-carregada de Get-AppxProvisionedPackage (otimizacao).
.PARAMETER InstalledList
    Lista pre-carregada de Get-AppxPackage -AllUsers (otimizacao).
.PARAMETER WingetId
    Se o pacote tambem deve ser desinstalado via winget (Win11 24H2 Copilot, etc).
#>
function Invoke-AppPackageRemoval {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [string]$Categoria,
        [string]$App,
        [object[]]$ProvisionedList,
        [object[]]$InstalledList,
        [string]$WingetId = ''
    )

    # 1. Apps protegidos
    if (-not $SkipProtectedCheck -and (Test-IsProtectedApp $App)) {
        Add-RemoveResult -Categoria $Categoria -App $App -Status 'PROTEGIDO' -Obs 'componente do sistema'
        Write-Warn "PROTEGIDO: $App (lista de apps criticos)"
        return
    }

    # 2. -WhatIf simula sem aplicar
    if (-not $PSCmdlet.ShouldProcess($App, 'Remover pacote Appx')) {
        Add-RemoveResult -Categoria $Categoria -App $App -Status 'SIMULADO' -Obs '-WhatIf'
        Write-Info "SIMULADO: $App"
        return
    }

    $remocaoSucesso = $false
    $obs = ''

    # 3. Provisioned (afeta novos usuarios)
    $provs = $ProvisionedList | Where-Object {
        $_.PackageName -like "$App*" -or $_.DisplayName -like "$App*"
    }
    if ($provs) {
        foreach ($p in $provs) {
            try {
                Remove-AppxProvisionedPackage -Online -PackageName $p.PackageName -ErrorAction Stop | Out-Null
                Write-Ok "Provisioned removido: $($p.DisplayName)"
                $remocaoSucesso = $true
            } catch {
                Write-Fail "Falha provisioned $($p.DisplayName): $($_.Exception.Message)"
                $obs = "provisioned: $($_.Exception.Message)"
            }
        }
    }

    # 4. Installed (afeta usuarios existentes)
    $insts = $InstalledList | Where-Object {
        $_.Name -like "$App*" -or $_.PackageFullName -like "$App*"
    }
    if ($insts) {
        foreach ($i in $insts) {
            try {
                Remove-AppxPackage -Package $i.PackageFullName -AllUsers -ErrorAction Stop | Out-Null
                Write-Ok "Removido: $($i.Name)"
                $remocaoSucesso = $true
            } catch {
                Write-Fail "Falha $($i.Name): $($_.Exception.Message)"
                $obs = "appx: $($_.Exception.Message)"
            }
        }
    }

    # 5. Winget (Win11 24H2+ Copilot, etc)
    if ($WingetId -and $script:Compat.HasWinget) {
        try {
            Write-Step "Tentando winget uninstall $WingetId..."
            $out = & winget uninstall --id $WingetId --silent --accept-source-agreements 2>&1 | Out-String
            if ($LASTEXITCODE -eq 0 -or $out -match 'No installed package found' -or $out -match 'Successfully uninstalled') {
                if ($out -match 'Successfully uninstalled') {
                    Write-Ok "winget removeu: $WingetId"
                    $remocaoSucesso = $true
                }
            }
        } catch {
            Write-Warn "winget falhou para $($WingetId): $($_.Exception.Message)"
        }
    }

    # 6. Resultado
    if ($remocaoSucesso) {
        Add-RemoveResult -Categoria $Categoria -App $App -Status 'REMOVIDO'
    } elseif (-not $provs -and -not $insts) {
        Add-RemoveResult -Categoria $Categoria -App $App -Status 'NAO_ENCONTRADO' -Obs 'nao instalado'
        Write-Info "Nao encontrado: $App"
    } else {
        Add-RemoveResult -Categoria $Categoria -App $App -Status 'FALHOU' -Obs $obs
    }
}

<#
.SYNOPSIS
    Desinstala o cliente Win32 do OneDrive (OneDriveSetup.exe /uninstall).
.DESCRIPTION
    O cliente OneDrive principal NAO e Appx. Reside em
    %LOCALAPPDATA%\Microsoft\OneDrive ou %SystemRoot%\System32\OneDriveSetup.exe.
#>
function Uninstall-OneDriveWin32 {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([string]$Categoria = 'OneDrive')

    if (-not $PSCmdlet.ShouldProcess('OneDrive Win32', 'Desinstalar cliente OneDrive')) {
        Add-RemoveResult -Categoria $Categoria -App 'OneDriveSetup.exe' -Status 'SIMULADO' -Obs '-WhatIf'
        return
    }

    $candidatos = @(
        "$env:SystemRoot\SysWOW64\OneDriveSetup.exe",
        "$env:SystemRoot\System32\OneDriveSetup.exe"
    )
    $setupPath = $candidatos | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

    if (-not $setupPath) {
        Add-RemoveResult -Categoria $Categoria -App 'OneDriveSetup.exe' -Status 'NAO_ENCONTRADO'
        Write-Info "OneDriveSetup.exe nao encontrado (cliente Win32 ja removido?)"
        return
    }

    try {
        Write-Step "Encerrando processos do OneDrive..."
        Get-Process -Name 'OneDrive' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

        Write-Step "Executando: $setupPath /uninstall"
        $proc = Start-Process -FilePath $setupPath -ArgumentList '/uninstall' -PassThru -Wait -ErrorAction Stop
        if ($proc.ExitCode -eq 0) {
            Write-Ok "OneDrive Win32 desinstalado."
            Add-RemoveResult -Categoria $Categoria -App 'OneDriveSetup.exe' -Status 'REMOVIDO'
        } else {
            Add-RemoveResult -Categoria $Categoria -App 'OneDriveSetup.exe' -Status 'FALHOU' -Obs "exit $($proc.ExitCode)"
        }

        # Limpa pasta residual
        Remove-Item "$env:USERPROFILE\OneDrive" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item "$env:LOCALAPPDATA\Microsoft\OneDrive" -Recurse -Force -ErrorAction SilentlyContinue
    } catch {
        Add-RemoveResult -Categoria $Categoria -App 'OneDriveSetup.exe' -Status 'FALHOU' -Obs $_.Exception.Message
        Write-Fail "Falha desinstalando OneDrive: $($_.Exception.Message)"
    }
}

function Set-RegistryDWordValue {
    param(
        [string]$Path,
        [string]$Name,
        [int]$Value,
        [System.Management.Automation.ActionPreference]$OnError = 'Continue'
    )

    New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType DWord -Force -ErrorAction $OnError | Out-Null
}

<#
.SYNOPSIS
    Aplica politicas via Registry para bloquear reinstalacao automatica de bloatware.
.DESCRIPTION
    Escreve em HKLM e HKCU multiplas chaves:
      - DisableWindowsConsumerFeatures (Pro/Enterprise/Server)
      - ContentDeliveryManager.* (12 chaves de pre-instalacao automatica)
      - WindowsStore.AutoDownload (impede auto-download da Store)
      - SilentInstalledAppsEnabled (Win11)
#>
function Block-AppReinstall {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param()

    if (-not $PSCmdlet.ShouldProcess('Registry', 'Bloquear reinstalacao automatica de apps')) {
        Write-Info "SIMULADO: bloqueio de reinstalacao via Registry."
        return
    }

    $changes = 0

    # 1. CloudContent (somente Pro+)
    if ($script:Compat.GpoApplica) {
        try {
            $regPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
            if (-not (Test-Path -LiteralPath $regPath)) {
                New-Item -Path $regPath -Force -ErrorAction Stop | Out-Null
            }
            Set-RegistryDWordValue -Path $regPath -Name 'DisableWindowsConsumerFeatures' -Value 1 -OnError Stop
            Set-RegistryDWordValue -Path $regPath -Name 'DisableConsumerAccountStateContent' -Value 1 -OnError SilentlyContinue
            Set-RegistryDWordValue -Path $regPath -Name 'DisableSoftLanding' -Value 1 -OnError SilentlyContinue
            Set-RegistryDWordValue -Path $regPath -Name 'DisableThirdPartySuggestions' -Value 1 -OnError SilentlyContinue
            Write-Ok "CloudContent: GPO aplicada (Pro/Enterprise)"
            $changes++
        } catch {
            Write-Fail "CloudContent: $($_.Exception.Message)"
        }
    } else {
        Write-Warn "CloudContent: pulado ($($script:Compat.Edition) nao suporta esta GPO)"
    }

    # 2. ContentDeliveryManager - HKLM (afeta novos usuarios) e HKCU (afeta usuario atual)
    $cdmKeys = @(
        'ContentDeliveryAllowed',
        'OemPreInstalledAppsEnabled',
        'PreInstalledAppsEnabled',
        'PreInstalledAppsEverEnabled',
        'SilentInstalledAppsEnabled',
        'SubscribedContent-310093Enabled',
        'SubscribedContent-314559Enabled',
        'SubscribedContent-338387Enabled',
        'SubscribedContent-338388Enabled',
        'SubscribedContent-338389Enabled',
        'SubscribedContent-338393Enabled',
        'SubscribedContent-353694Enabled',
        'SubscribedContent-353696Enabled',
        'SubscribedContent-353698Enabled',
        'SystemPaneSuggestionsEnabled'
    )
    foreach ($scope in @('HKLM','HKCU')) {
        $cdmPath = "${scope}:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
        try {
            if (-not (Test-Path -LiteralPath $cdmPath)) {
                New-Item -Path $cdmPath -Force -ErrorAction Stop | Out-Null
            }
            foreach ($k in $cdmKeys) {
                Set-RegistryDWordValue -Path $cdmPath -Name $k -Value 0 -OnError SilentlyContinue
            }
            Write-Ok "${scope}\ContentDeliveryManager: $($cdmKeys.Count) chaves desativadas"
            $changes++
        } catch {
            Write-Fail "${scope}\ContentDeliveryManager: $($_.Exception.Message)"
        }
    }

    # 3. WindowsStore - bloqueia auto-download
    if ($script:Compat.GpoApplica) {
        try {
            $storePath = 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore'
            if (-not (Test-Path -LiteralPath $storePath)) {
                New-Item -Path $storePath -Force -ErrorAction Stop | Out-Null
            }
            Set-RegistryDWordValue -Path $storePath -Name 'AutoDownload' -Value 2 -OnError Stop
            Write-Ok "WindowsStore: AutoDownload desativado"
            $changes++
        } catch {
            Write-Fail "WindowsStore: $($_.Exception.Message)"
        }
    }

    Write-Info "Total de chaves alteradas: $changes"
}

# ----------------------------------------------------------
# Menu interativo / nao-interativo
# ----------------------------------------------------------
function Get-CategoriasParaRemover {
    if (-not $script:ForceMenu) {
        if ($Tudo) { return $script:AppsCatalog.Keys }
        if ($Apps) { return $Apps }
    }

    # Modo interativo
    Write-Host "  Selecione as categorias a remover (numeros separados por virgula):" -ForegroundColor White
    Write-Host ""

    $i = 1
    $idx = @{}
    foreach ($cat in $script:AppsCatalog.Keys) {
        $info = $script:AppsCatalog[$cat]
        Write-Host ("  [{0,2}] {1}" -f $i, $info.Display) -ForegroundColor Yellow
        $idx[$i.ToString()] = $cat
        $i++
    }
    $totalIdx = $i - 1
    Write-Host ""
    Write-Host ("  [{0,2}] TUDO (todas as categorias acima)" -f ($totalIdx + 1)) -ForegroundColor Red
    Write-Host  "  [ 0] Cancelar" -ForegroundColor Yellow
    Write-Host ""

    do {
        $input = Read-Host "  Digite as opcoes (ex: 1,3,5) ou 0 para cancelar"
        if ($input -eq '0') { return @() }

        $partes = $input -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        $selecionadas = @()
        $invalidas = @()

        foreach ($p in $partes) {
            if ($p -eq ($totalIdx + 1).ToString()) {
                return $script:AppsCatalog.Keys
            }
            if ($idx.ContainsKey($p)) {
                $selecionadas += $idx[$p]
            } else {
                $invalidas += $p
            }
        }

        if ($invalidas.Count -gt 0) {
            Write-Fail "Opcoes invalidas: $($invalidas -join ', ')"
            continue
        }

        if ($selecionadas.Count -gt 0) {
            return $selecionadas | Sort-Object -Unique
        }
        Write-Fail "Nenhuma opcao valida selecionada."
    } while ($true)
}

# ============================================================
# MAIN
# ============================================================
try {

while ($true) {
    $script:RemoveResults = @()
    $script:ScriptStartTime = Get-Date
    Write-Banner

    if ($script:Compat.WindowsVer -eq 'Server') {
        Write-Warn "Detectado Windows Server. Alguns apps consumer nem existem nesta edicao."
    }

    # Resolve categorias
    $categorias = Get-CategoriasParaRemover
    if (-not $categorias -or $categorias.Count -eq 0) {
        Write-Warn "Nenhuma categoria selecionada. Encerrando."
        break
    }

    # Mostra plano
    Write-Host ""
    Write-Host "  Categorias selecionadas:" -ForegroundColor White
    foreach ($c in $categorias) {
        Write-Host ("    - {0}: {1}" -f $c, $script:AppsCatalog[$c].Display) -ForegroundColor Cyan
    }
    Write-Host ""

    if (-not $script:NonInteractive) {
        if (-not (Confirm-Tecla "Confirmar remocao?")) {
            Write-Warn "Operacao cancelada."
            break
        }
    }

    # Carrega listas de pacotes UMA VEZ (otimizacao)
    Write-Phase "Carregando inventario Appx"
    Write-Step "Listando provisioned packages..."
    $provisionedList = @()
    try { $provisionedList = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop) } catch {
        Write-Warn "Get-AppxProvisionedPackage falhou: $($_.Exception.Message)"
    }
    Write-Step "Listando installed packages (-AllUsers)..."
    $installedList = @()
    try { $installedList = @(Get-AppxPackage -AllUsers -ErrorAction Stop) } catch {
        Write-Warn "Get-AppxPackage -AllUsers falhou: $($_.Exception.Message)"
    }
    Write-Ok "Provisioned: $($provisionedList.Count) pacotes  |  Installed: $($installedList.Count) pacotes"

    # Itera categorias
    foreach ($cat in $categorias) {
        $info = $script:AppsCatalog[$cat]
        Write-Phase "$cat - $($info.Display)"

        foreach ($app in $info.Apps) {
            $wingetId = if ($info.PSObject.Properties['Winget']) { $info.Winget } else { '' }
            Invoke-AppPackageRemoval -Categoria $cat -App $app `
                -ProvisionedList $provisionedList `
                -InstalledList $installedList `
                -WingetId $wingetId
        }

        # Tratamento especial: OneDrive Win32
        if ($cat -eq 'OneDrive' -and $info.PSObject.Properties['Win32'] -and $info.Win32) {
            Uninstall-OneDriveWin32 -Categoria $cat
        }
    }

    # Bloqueio de reinstalacao
    if (-not $NoBlockReinstall) {
        Write-Phase "Bloqueio de reinstalacao automatica"
        Block-AppReinstall
    } else {
        Write-Info "Bloqueio de reinstalacao pulado (-NoBlockReinstall)."
    }

    # Resumo final
    Show-Summary

    if (Confirm-VoltarMenu) {
        $script:ForceMenu = $true
        continue
    }

    break
}

} catch {
    Write-Host ""
    Write-Host "  $($script:SymFail) Erro fatal: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  Linha: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
    if (-not $script:NonInteractive) {
        Read-Host "Pressione ENTER para fechar"
    }
    exit 1
} finally {
    if ($script:TranscriptStarted) {
        try { Stop-Transcript | Out-Null } catch { }
    }
}
