<#
.SYNOPSIS
    Script de limpeza abrangente de arquivos temporários, caches e pastas desnecessárias.

.DESCRIPTION
    Executa limpeza em pastas Adobe, caches de navegadores (Chrome, Edge, Firefox, Teams),
    arquivos temporários e Downloads, utilizando jobs para paralelismo e exibindo progresso.
    Exclui arquivos antigos conforme datas configuráveis e preserva arquivos protegidos.
    Mantém apenas N snapshots mais recentes do Chrome/Edge (por padrão, 1).
    Mantém dados de WebStorage (Local/Session Storage) apenas dos últimos N dias.
    Limpa IndexedDB mantendo apenas dados recentes configuráveis.

.NOTES
    Autor       : Victor Hugo Gomides
    Empresa     : Infinity Brasil Ltda
    Telefone    : (34) 3301-2900
    Data criação: 2024-12-14
    Última modif: 2026-04-10
    Versão      : 3.9.9
    RequerAdmin : Sim

.CHANGELOG
    1.0  – 14/12/2024 – Criação do script (limpeza básica de Adobe, caches, temp e Downloads).
    2.0  – 12/02/2025 – Melhoria visual / organização dos blocos e comentários.
    3.0  – 22/03/2025 – Refatoração geral; funções isoladas e suporte a jobs paralelos.
    3.1  – 08/05/2025 – Adicionada função Write-Log (timestamp + nível).
    3.2  – 13/05/2025 – Inclusa função Limpar-Insomnia (mantém só a versão mais recente).
    3.3  – 14/05/2025 – Inclusa função Limpar-NuGetCaches + variável $limparNuGetCache.
    3.4  – 14/05/2025 – Inclusa função Limpar-NpmCache + variável $limparNpmCache.
           • 3.4.x   – correções menores, verificação sequencial do npm, etc.
    3.5.0 – 12/09/2025 – NOVO: Limpar-ChromeSnapshots (Chrome/Edge) + variável $manterSnapshots;
                         revisão e ajuste de sintaxe no Limpar-NpmCache.
    3.6.0 – 17/09/2025 – NOVO: Limpar-WebStorageSeletivo (Chrome/Edge) + variáveis $limparWebStorage e $diasWebStorage.
    3.6.1 – 17/09/2025 – Adicionados novos canais no Limpar-WebStorageSeletivo.
    3.6.2 – 18/09/2025 – Adequação de política: não encerrar processos; limpeza best-effort com log de bloqueios.
    3.7.0 – 12/02/2026 – NOVO: Limpar-IndexedDB (Chrome/Edge) + variáveis $limparIndexedDB e $diasIndexedDB.
    3.9.9 - 29/04/2026 - UX: banner compacto sem moldura e terminal preferencialmente maior.
    3.9.8 - 29/04/2026 - Ajuste: Write-Log nao grava arquivo para evitar acumulo em agendador.
    3.9.7 - 29/04/2026 - UX: autoelevacao prefere Windows Terminal/tela preta quando disponivel.
    3.9.6 - 29/04/2026 - Fix: Console OutputEncoding protegido para hosts sem console valido.
    3.9.5 - 29/04/2026 - Fix: reescrita limpa do Limpar-ChromeSnapshots para evitar parser error em copias.
    3.9.4 - 29/04/2026 - Fix: Limpar-NpmCache com sintaxe conservadora PS5.1 e Write-Log nomeado.
    3.9.3 - 29/04/2026 - Fix: reescrita limpa do Limpar-NpmCache para evitar copia truncada/parser error.
    3.9.2 – 29/04/2026 – Fix: autoelevação usa -NoExit e wrapper de erro para evitar fechamento imediato.
    3.9.1 – 29/04/2026 – Fix: autoelevação mais robusta e pausa final/erro em modo interativo.
    3.9.0 – 28/04/2026 – Visual: banner/fases/resumo no padrão ia-install sem alterar escopo de limpeza.
    3.8.0 – 10/04/2026 – Correções: $ErrorActionPreference='Stop'; log em arquivo (C:\Logs\); auto-elevação
                         detecta PS5/PS7 automaticamente; separação pastasRelativas/pastasAbsolutas;
                         Limpar-Adobe recebe DiasCorte como parâmetro; fix output duplicado nos jobs;
                         Receive-Job final no NuGet paralelo.
#>

# =================== CONFIGURAÇÃO GLOBAL ===================

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch {
    # Alguns hosts/elevacoes nao possuem handle de console valido.
}

$SCRIPT_VERSION = '3.9.9'
$SCRIPT_DATA    = '29/04/2026'
try {
    $script:NonInteractive = [Console]::IsInputRedirected -or (-not [Environment]::UserInteractive)
} catch {
    $script:NonInteractive = $false
}

function Wait-Final {
    param([string]$Mensagem = "Pressione ENTER para fechar")
    if ($script:NonInteractive) { return }
    try {
        Write-Host ""
        Read-Host $Mensagem | Out-Null
    } catch { }
}

$script:SymOk     = 'OK'
$script:SymFail   = 'ERRO'
$script:SymWarn   = 'AVISO'
$script:SymStep   = '>'
$script:SymInfo   = 'INFO'
$script:BoxTL = '+'; $script:BoxTR = '+'; $script:BoxBL = '+'; $script:BoxBR = '+'
$script:BoxH = '-';  $script:BoxV = '|'

# =================== VARIÁVEIS CONFIGURÁVEIS ===================

# Requer privilégio administrativo? ("sim" ou "não")
$RequerAdmin = "sim"

# Limpar o cache global do NuGet em todos os usuários?  ("sim" ou "não")
$limparNuGetCache = "não"

# Limpar o npm-cache em todos os usuários? ("sim" ou "não")
$limparNpmCache = "não"

# Quantos snapshots manter (Chrome/Edge) por canal. 1 = manter somente o mais recente
$manterSnapshots = 1

# Manter WebStorage recente? ("sim" ou "não") e janela de retenção em dias
$limparWebStorage = "sim"
$diasWebStorage   = 2

# Limpar IndexedDB? ("sim" ou "não") e janela de retenção em dias
$limparIndexedDB = "sim"
$diasIndexedDB   = 2

# Número de dias para considerar arquivos antigos na pasta Adobe
$dataDeCorteAdobe = 30

# Quantidade de dias para considerar arquivos antigos na pasta Downloads (arquivos modificados antes desta data serão excluídos)
$diasDownloads = 10

# Lista de arquivos que não devem ser excluídos da pasta Downloads
$naoExcluirDownloads = @("desktop.ini")

# Lista de caminhos dos caches dos navegadores e aplicativos a serem limpos
$caminhosBrowsers = @(
    "C:\Users\*\AppData\Local\Google\Chrome\User Data\Profile *\Cache\*",
    "C:\Users\*\AppData\Local\Google\Chrome\User Data\Profile *\Code Cache\*",
    "C:\Users\*\AppData\Local\Google\Chrome\User Data\Profile *\Service Worker\*",
    "C:\Users\*\AppData\Local\Google\Chrome\User Data\Default\Cache\*",
    "C:\Users\*\AppData\Local\Google\Chrome\User Data\Default\Code Cache\*",
    "C:\Users\*\AppData\Local\Google\Chrome\User Data\Default\Service Worker\*",

    # ChromeDEV
    "C:\Users\*\AppData\Local\Google\Chrome Dev\User Data\Profile *\Cache\*",
    "C:\Users\*\AppData\Local\Google\Chrome Dev\User Data\Profile *\Code Cache\*",
    "C:\Users\*\AppData\Local\Google\Chrome Dev\User Data\Profile *\Service Worker\*",
    "C:\Users\*\AppData\Local\Google\Chrome Dev\User Data\Default\Cache\*",
    "C:\Users\*\AppData\Local\Google\Chrome Dev\User Data\Default\Code Cache\*",
    "C:\Users\*\AppData\Local\Google\Chrome Dev\User Data\Default\Service Worker\*",

    # Edge - perfis múltiplos e padrão
    "C:\Users\*\AppData\Local\Microsoft\Edge\User Data\Profile *\Cache\*",
    "C:\Users\*\AppData\Local\Microsoft\Edge\User Data\Profile *\Code Cache\*",
    "C:\Users\*\AppData\Local\Microsoft\Edge\User Data\Profile *\Service Worker\*",
    "C:\Users\*\AppData\Local\Microsoft\Edge\User Data\Default\Cache\*",
    "C:\Users\*\AppData\Local\Microsoft\Edge\User Data\Default\Code Cache\*",
    "C:\Users\*\AppData\Local\Microsoft\Edge\User Data\Default\Service Worker\*",
    
    # Firefox
    "C:\Users\*\AppData\local\Mozilla\Firefox\Profiles\*\cache2\entries\*.",
    "C:\Users\*\AppData\local\Mozilla\Firefox\Profiles\*\startupCache\*.bin",
    "C:\Users\*\AppData\local\Mozilla\Firefox\Profiles\*\startupCache\*.lz*",
    "C:\Users\*\AppData\local\Mozilla\Firefox\Profiles\*\cache2\index*.*",
    "C:\Users\*\AppData\local\Mozilla\Firefox\Profiles\*\startupCache\*.little",
    "C:\Users\*\AppData\local\Mozilla\Firefox\Profiles\*\cache2\*.log"
)

# Pastas relativas ao perfil de cada usuário (serão combinadas com C:\Users\<usuario>\)
$pastasRelativas = @(
    "AppData\Local\Microsoft\Terminal Server Client\Cache\",
    "AppData\Local\Microsoft\Windows\Explorer\",
    "AppData\Local\Microsoft\Windows\INetCache\",
    "AppData\Local\Yarn\Cache\v6\",
    "AppData\Roaming\Code\Cache\",
    "AppData\Roaming\Code\CachedData\",
    "AppData\Roaming\Code\CachedExtensionVSIXs\",
    "AppData\Local\Temp\"
)

# Caminhos absolutos com wildcard para pastas de aplicativos (Teams, etc.)
$pastasAbsolutas = @(
    "C:\Users\*\AppData\Roaming\Microsoft\Teams\Service Worker\*",
    "C:\Users\*\AppData\Roaming\Microsoft\Teams\Partitions\msa\Service Worker\*",
    "C:\Users\*\AppData\Roaming\Microsoft\Teams\Partitions\msa\Cache\*",
    "C:\Users\*\AppData\Roaming\Microsoft\Teams\Partitions\msa\Code Cache\*",
    "C:\Users\*\AppData\Local\Microsoft\Terminal Server Client\*"
)

# Pastas do sistema operacional que devem ser limpas
$pastasSistema = @(
    "C:\Windows\Temp\",
    "C:\Windows\SoftwareDistribution\"
)

# =================== SOLICITAÇÃO DE PRIVILÉGIO ===================

if ($RequerAdmin -notin @("sim", "não")) {
    Write-Warning "Valor inválido para RequerAdmin. Use 'sim' ou 'não'."
    exit 1
}

if ($RequerAdmin -eq "sim") {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "O script precisa ser executado como Administrador. Solicitando elevacao..." -ForegroundColor Yellow

        $cmdPath = $PSCommandPath
        if (-not $cmdPath) { $cmdPath = $MyInvocation.PSCommandPath }
        if (-not $cmdPath) { $cmdPath = $MyInvocation.MyCommand.Path }

        if (-not ($cmdPath -and (Test-Path -LiteralPath $cmdPath))) {
            Write-Host "Nao foi possivel localizar o arquivo do script para elevar." -ForegroundColor Red
            Wait-Final
            exit 1
        }

        try {
            $shellPath = "powershell.exe"
            try {
                $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
                if ($pwsh) { $shellPath = $pwsh.Source }
            } catch { }

            $wtPath = $null
            if (-not $script:NonInteractive) {
                try {
                    $wt = Get-Command wt.exe -ErrorAction SilentlyContinue
                    if ($wt) { $wtPath = $wt.Source }
                } catch { }

                if (-not $wtPath) {
                    $wtCandidate = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\wt.exe"
                    if (Test-Path -LiteralPath $wtCandidate) { $wtPath = $wtCandidate }
                }
            }

            $escapedPath = $cmdPath.Replace("'", "''")
            $command = @"
try {
    try {
        `$Host.UI.RawUI.BackgroundColor = 'Black'
        `$Host.UI.RawUI.ForegroundColor = 'White'
        `$raw = `$Host.UI.RawUI
        `$buffer = `$raw.BufferSize
        if (`$buffer.Width -lt 140) { `$buffer.Width = 140 }
        if (`$buffer.Height -lt 3000) { `$buffer.Height = 3000 }
        `$raw.BufferSize = `$buffer
        `$window = `$raw.WindowSize
        if (`$window.Width -lt 140) { `$window.Width = 140 }
        if (`$window.Height -lt 42) { `$window.Height = 42 }
        `$raw.WindowSize = `$window
        Clear-Host
    } catch { }
    & '$escapedPath'
} catch {
    Write-Host ''
    Write-Host ('ERRO: ' + `$_.Exception.Message) -ForegroundColor Red
    Write-Host ('Linha: ' + `$_.InvocationInfo.ScriptLineNumber) -ForegroundColor Red
}
"@

            if ($wtPath) {
                $wtArgs = @(
                    '-w', '-1',
                    '--size', '140,42',
                    'new-tab',
                    '--title', 'delete-temp-files',
                    '--suppressApplicationTitle',
                    '--',
                    $shellPath,
                    '-NoExit',
                    '-NoProfile',
                    '-ExecutionPolicy', 'Bypass',
                    '-Command', $command
                )
                Start-Process -FilePath $wtPath -Verb RunAs -ArgumentList $wtArgs -ErrorAction Stop | Out-Null
            } else {
                $argList = @(
                    '-NoExit',
                    '-NoProfile',
                    '-ExecutionPolicy', 'Bypass',
                    '-Command', $command
                )
                Start-Process -FilePath $shellPath -Verb RunAs -ArgumentList $argList -ErrorAction Stop | Out-Null
            }

            exit 0
        } catch {
            Write-Host "Elevacao cancelada ou falhou: $($_.Exception.Message)" -ForegroundColor Red
            Wait-Final
            exit 1
        }
    }
}

if ($limparNuGetCache -notin @("sim", "não")) {
    Write-Warning "Valor inválido para limparNuGetCache. Use 'sim' ou 'não'."
    exit 1
}

if ($limparNpmCache -notin @("sim", "não")) {
    Write-Warning "Valor inválido para limparNpmCache. Use 'sim' ou 'não'."
    exit 1
}

if ($limparWebStorage -notin @("sim", "não")) {
    Write-Warning "Valor inválido para limparWebStorage. Use 'sim' ou 'não'."
    exit 1
}

if ($limparIndexedDB -notin @("sim", "não")) {
    Write-Warning "Valor inválido para limparIndexedDB. Use 'sim' ou 'não'."
    exit 1
}



# =================== FUNÇÃO DE LOG ===================

function Write-Log {
    param (
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $msg = "$timestamp [$Level] $Message"
    Write-Host $msg
}

# =================== FUNCOES DE INTERFACE ===================

function Write-Step  { param($msg) Write-Host ("  {0} {1}" -f $script:SymStep, $msg) -ForegroundColor Cyan }
function Write-Ok    { param($msg) Write-Host ("  {0} {1}" -f $script:SymOk,   $msg) -ForegroundColor Green }
function Write-Warn  { param($msg) Write-Host ("  {0} {1}" -f $script:SymWarn, $msg) -ForegroundColor Yellow }
function Write-Fail  { param($msg) Write-Host ("  {0} {1}" -f $script:SymFail, $msg) -ForegroundColor Red }
function Write-Info  { param($msg) Write-Host ("  {0} {1}" -f $script:SymInfo, $msg) -ForegroundColor Gray }

$script:CleanResults = @()
$script:ScriptStartTime = $null

function Add-CleanResult {
    param(
        [string]$Categoria,
        [string]$Alvo,
        [ValidateSet("OK", "PULADO", "FALHOU")]
        [string]$Status,
        [string]$Obs = ''
    )
    $script:CleanResults += [PSCustomObject]@{
        Categoria = $Categoria
        Alvo      = $Alvo
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

    $ok   = @($script:CleanResults | Where-Object { $_.Status -eq "OK" }).Count
    $skip = @($script:CleanResults | Where-Object { $_.Status -eq "PULADO" }).Count
    $fail = @($script:CleanResults | Where-Object { $_.Status -eq "FALHOU" }).Count
    $headerColor = if ($fail -gt 0) { "Red" } else { "Green" }
    $headerLabel = if ($fail -gt 0) { "CONCLUIDO COM FALHAS" } else { "LIMPEZA CONCLUIDA" }

    $hLine = ([string]$script:BoxH) * 61
    Write-Host ""
    Write-Host ("  $($script:BoxTL)$hLine$($script:BoxTR)") -ForegroundColor Cyan
    $linha1 = "  RESUMO  (tempo total: $elapsedStr)".PadRight(61)
    Write-Host ("  $($script:BoxV)$linha1$($script:BoxV)") -ForegroundColor White
    $linha2 = "  - $headerLabel  ($ok ok / $skip pulados / $fail falhas)".PadRight(61)
    if ($linha2.Length -gt 61) { $linha2 = $linha2.Substring(0, 61) }
    Write-Host ("  $($script:BoxV)$linha2$($script:BoxV)") -ForegroundColor $headerColor
    Write-Host ("  $($script:BoxBL)$hLine$($script:BoxBR)") -ForegroundColor Cyan

    foreach ($r in $script:CleanResults) {
        $cor = if ($r.Status -eq "OK") { "Green" } elseif ($r.Status -eq "PULADO") { "DarkGray" } else { "Red" }
        $obs = if ($r.Obs) { " $($r.Obs)" } else { "" }
        Write-Host ("    {0,-18} {1,-34} [{2}]{3}" -f $r.Categoria, $r.Alvo, $r.Status, $obs) -ForegroundColor $cor
    }
    Write-Host ""
}

function Set-PreferredConsoleSize {
    param([int]$Width = 140, [int]$Height = 42)

    try {
        $raw = $Host.UI.RawUI
        $buffer = $raw.BufferSize
        if ($buffer.Width -lt $Width) { $buffer.Width = $Width }
        if ($buffer.Height -lt 3000) { $buffer.Height = 3000 }
        $raw.BufferSize = $buffer

        $max = $raw.MaxWindowSize
        $targetWidth = [Math]::Min($Width, $max.Width)
        $targetHeight = [Math]::Min($Height, $max.Height)
        $window = $raw.WindowSize
        if ($window.Width -lt $targetWidth) { $window.Width = $targetWidth }
        if ($window.Height -lt $targetHeight) { $window.Height = $targetHeight }
        $raw.WindowSize = $window
    } catch { }
}

function Write-Banner {
    Set-PreferredConsoleSize
    try { Clear-Host } catch { }
    Write-Host ""
    Write-Host "  D E L E T E - T E M P - F I L E S" -ForegroundColor White
    Write-Host ("  Limpeza de temporarios, caches e downloads | v{0}" -f $SCRIPT_VERSION) -ForegroundColor DarkCyan
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

function Confirm-Tecla {
    param([string]$Mensagem)
    if ($script:NonInteractive) { return $true }

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

# =================== FUNÇÃO: MANTER APENAS N SNAPSHOTS (CHROME/EDGE) ===================

function Limpar-ChromeSnapshots {
    param(
        [int]$Manter = 1,
        [switch]$Paralelo
    )

    if ($Manter -lt 0) { $Manter = 0 }

    Write-Log -Message ("Iniciando limpeza de Snapshots Chrome Edge. Manter {0}" -f $Manter) -Level "INFO"

    $canais = @(
        [PSCustomObject]@{ Nome = "Chrome";        Base = "Google\Chrome" },
        [PSCustomObject]@{ Nome = "Chrome Beta";   Base = "Google\Chrome Beta" },
        [PSCustomObject]@{ Nome = "Chrome Dev";    Base = "Google\Chrome Dev" },
        [PSCustomObject]@{ Nome = "Chrome Canary"; Base = "Google\Chrome SxS" },
        [PSCustomObject]@{ Nome = "Edge";          Base = "Microsoft\Edge" }
    )

    $userFolders = Get-ChildItem -LiteralPath "C:\Users" -Directory -ErrorAction SilentlyContinue

    $snapshotScript = {
        param(
            [string]$SnapPath,
            [int]$KeepCount,
            [string]$BrowserName,
            [string]$UserName
        )

        try {
            if (-not (Test-Path -LiteralPath $SnapPath)) {
                Write-Output ("[{0}][{1}] Pasta nao encontrada: {2}" -f $UserName, $BrowserName, $SnapPath)
                return
            }

            $dirs = Get-ChildItem -LiteralPath $SnapPath -Directory -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending

            if (-not $dirs -or $dirs.Count -le $KeepCount) {
                Write-Output ("[{0}][{1}] Nada para excluir em {2}" -f $UserName, $BrowserName, $SnapPath)
                return
            }

            $keep = @($dirs | Select-Object -First $KeepCount)
            $delete = @($dirs | Select-Object -Skip $KeepCount)

            foreach ($dir in $delete) {
                try {
                    Remove-Item -LiteralPath $dir.FullName -Recurse -Force -ErrorAction Stop
                    Write-Output ("[{0}][{1}] Snapshot excluido: {2}" -f $UserName, $BrowserName, $dir.Name)
                } catch {
                    Write-Output ("[{0}][{1}] Falha ao excluir {2}: {3}" -f $UserName, $BrowserName, $dir.FullName, $_.Exception.Message)
                }
            }

            $keptNames = ($keep | ForEach-Object { $_.Name }) -join ", "
            Write-Output ("[{0}][{1}] Mantido: {2}" -f $UserName, $BrowserName, $keptNames)
        } catch {
            Write-Output ("[{0}][{1}] Erro ao processar {2}: {3}" -f $UserName, $BrowserName, $SnapPath, $_.Exception.Message)
        }
    }

    $jobs = @()

    foreach ($user in $userFolders) {
        foreach ($canal in $canais) {
            $relativePath = "AppData\Local\{0}\User Data\Snapshots" -f $canal.Base
            $snapPath = Join-Path -Path $user.FullName -ChildPath $relativePath

            if ($Paralelo) {
                $jobs += Start-Job -ScriptBlock $snapshotScript -ArgumentList $snapPath, $Manter, $canal.Nome, $user.Name
            } else {
                $out = & $snapshotScript $snapPath $Manter $canal.Nome $user.Name
                foreach ($line in $out) {
                    Write-Log -Message $line -Level "INFO"
                }
            }
        }
    }

    if ($Paralelo -and $jobs.Count -gt 0) {
        $jobs | Wait-Job | Out-Null

        foreach ($job in $jobs) {
            $out = Receive-Job -Job $job -ErrorAction SilentlyContinue
            foreach ($line in $out) {
                Write-Log -Message $line -Level "INFO"
            }
        }

        $jobs | Remove-Job -Force -ErrorAction SilentlyContinue
    }

    Write-Log -Message "Limpeza de Snapshots Chrome Edge finalizada" -Level "INFO"
}

# =================== FUNÇÃO: LIMPAR CACHE NUGET ===================

function Limpar-NuGetCaches {
    <#
        .SYNOPSIS
            Remove C:\Users\<user>\.nuget\packages para todos os perfis.
        .PARAMETER Paralelo
            Quando presente, executa em jobs paralelos.
    #>
    param (
        [switch]$Paralelo
    )

    Write-Log "Iniciando limpeza do cache NuGet (global-packages) para todos os perfis" "INFO"

    $userFolders = Get-ChildItem -Path "C:\Users" -Directory -ErrorAction SilentlyContinue
    $jobs = @()

    foreach ($userFolder in $userFolders) {
        $nugetPath = Join-Path $userFolder.FullName ".nuget\packages"
        if (Test-Path $nugetPath) {
            if ($Paralelo) {
                $jobs += Start-Job -ScriptBlock {
                    param($path)
                    try {
                        Remove-Item -Path $path -Recurse -Force -ErrorAction Stop
                        Write-Output "Cache NuGet removido: $path"
                    } catch {
                        Write-Output "Erro ao remover cache NuGet: $path - $_"
                    }
                } -ArgumentList $nugetPath
            }
            else {
                try {
                    Remove-Item -Path $nugetPath -Recurse -Force -ErrorAction Stop
                    Write-Log "Cache NuGet removido: $nugetPath" "INFO"
                } catch {
                    Write-Log "Erro ao remover cache NuGet: $nugetPath - $_" "WARN"
                }
            }
        }
    }

    if ($Paralelo -and $jobs.Count) {
        while ($jobs.State -contains 'Running') {
            foreach ($job in $jobs) {
                $output = Receive-Job -Job $job -Keep
                foreach ($linha in $output) { Write-Host $linha }
            }
            Start-Sleep 1
        }
        foreach ($job in $jobs) {
            $output = Receive-Job -Job $job
            foreach ($linha in $output) { Write-Host $linha }
        }
        $jobs | Remove-Job
    }

    Write-Log "Limpeza do cache NuGet finalizada" "INFO"
}

# =================== FUNÇÃO: LIMPAR NPM CACHE (sem encerrar processos) ===================

function Limpar-NpmCache {
    param([switch]$Paralelo)

    Write-Log -Message "Iniciando limpeza do npm cache em todos os perfis sem encerrar processos" -Level "INFO"

    $npmExe = $null
    try {
        $cmdNpm = Get-Command npm -ErrorAction SilentlyContinue
        if ($cmdNpm) { $npmExe = $cmdNpm.Source }
    } catch {
        $npmExe = $null
    }

    if (-not $npmExe) {
        Write-Log -Message "npm.exe nao encontrado no PATH. Sera feita somente a limpeza fisica." -Level "WARN"
    }

    $userFolders = Get-ChildItem -LiteralPath "C:\Users" -Directory -ErrorAction SilentlyContinue
    $cachePaths = @()

    foreach ($user in $userFolders) {
        $cachePaths += Join-Path -Path $user.FullName -ChildPath "AppData\Local\npm-cache"
        $cachePaths += Join-Path -Path $user.FullName -ChildPath "AppData\Roaming\npm-cache"
    }

    $cleanScript = {
        param([string]$CachePath)

        try {
            if (-not (Test-Path -LiteralPath $CachePath)) {
                New-Item -ItemType Directory -Path $CachePath -Force -ErrorAction SilentlyContinue | Out-Null
            }

            try {
                & icacls.exe $CachePath /grant "*S-1-5-32-544:(OI)(CI)(F)" /T /C | Out-Null
            } catch {
                Write-Output ("Aviso ao ajustar permissoes em {0}: {1}" -f $CachePath, $_.Exception.Message)
            }

            $items = Get-ChildItem -LiteralPath $CachePath -Recurse -Force -ErrorAction SilentlyContinue
            foreach ($item in $items) {
                Remove-Item -LiteralPath $item.FullName -Force -Recurse -ErrorAction SilentlyContinue
            }

            Write-Output ("npm cache limpo em {0}" -f $CachePath)
        } catch {
            Write-Output ("Falha ao limpar {0}: {1}" -f $CachePath, $_.Exception.Message)
        }
    }

    $jobs = @()
    foreach ($cachePath in $cachePaths) {
        if ($Paralelo) {
            $jobs += Start-Job -ScriptBlock $cleanScript -ArgumentList $cachePath
        } else {
            $out = & $cleanScript $cachePath
            foreach ($line in $out) {
                if ($line -like "Falha*") {
                    Write-Log -Message $line -Level "WARN"
                } else {
                    Write-Log -Message $line -Level "INFO"
                }
            }
        }
    }

    if ($Paralelo -and $jobs.Count -gt 0) {
        $jobs | Wait-Job | Out-Null

        foreach ($job in $jobs) {
            $out = Receive-Job -Job $job -ErrorAction SilentlyContinue
            foreach ($line in $out) {
                if ($line -like "Falha*") {
                    Write-Log -Message $line -Level "WARN"
                } else {
                    Write-Log -Message $line -Level "INFO"
                }
            }
        }

        $jobs | Remove-Job -Force -ErrorAction SilentlyContinue
    }

    if ($npmExe) {
        foreach ($cachePath in $cachePaths) {
            if (-not (Test-Path -LiteralPath $cachePath)) { continue }

            try {
                & $npmExe cache verify --cache "$cachePath" --silent 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0) {
                    Write-Log -Message ("npm verify retornou codigo {0} em {1}" -f $LASTEXITCODE, $cachePath) -Level "WARN"
                }
            } catch {
                Write-Log -Message ("Erro no npm verify para {0}: {1}" -f $cachePath, $_.Exception.Message) -Level "WARN"
            }
        }
    }

    Write-Log -Message "Limpeza e verificacao do npm cache concluidas" -Level "INFO"
}

# =================== FUNÇÃO: LIMPAR WEBSTORAGE SELETIVO (sem encerrar processos) ===================

function Limpar-WebStorageSeletivo {
    <#
        .SYNOPSIS
            Remove pastas antigas de WebStorage (Local/Session Storage) e mantém apenas as mais recentes.
        .PARAMETER Dias
            Janela de retenção em dias (default = 30).
        .PARAMETER Paralelo
            Quando presente, processa caminhos em jobs paralelos.
    #>
    param(
        [int]$Dias = 30,
        [switch]$Paralelo
    )

    if ($Dias -lt 0) { $Dias = 0 }
    $cutoff = (Get-Date).AddDays(-$Dias)
    Write-Log "Iniciando limpeza seletiva do WebStorage (mantendo ultimos $Dias dia(s))" "INFO"

    # Apenas detectar processos abertos (não encerrar)
    $procs = "chrome","msedge","chrome.exe","msedge.exe"
    $emExec = Get-Process -ErrorAction SilentlyContinue | Where-Object { $procs -contains $_.Name }
    if ($emExec) {
        $lista = ($emExec | Select-Object -ExpandProperty Name | Sort-Object -Unique) -join ", "
        Write-Log "Navegadores em execucao detectados: $lista. Nao serao encerrados; limpeza podera pular itens bloqueados." "WARN"
    }

    # Canais / bases a varrer
    $canais = @(
        @{ Nome = "Chrome";        Base = "Google\Chrome" }
        @{ Nome = "Chrome Beta";   Base = "Google\Chrome Beta" }
        @{ Nome = "Chrome Dev";    Base = "Google\Chrome Dev" }
        @{ Nome = "Chrome Canary"; Base = "Google\Chrome SxS" }
        @{ Nome = "Edge";          Base = "Microsoft\Edge" }
    )

    $userFolders = Get-ChildItem -Path "C:\Users" -Directory -ErrorAction SilentlyContinue

    $sb = {
        param($wsPath, $usuario, $navegador, $dtcorte)

        if (-not (Test-Path $wsPath)) { return "[$usuario][$navegador] WebStorage nao encontrado: $wsPath" }

        # Apagar somente subpastas numeradas (IDs internos de sites) mais antigas que a data de corte.
        $alvos = Get-ChildItem -LiteralPath $wsPath -Directory -ErrorAction SilentlyContinue |
                 Where-Object { $_.Name -match '^\d+$' -and $_.LastWriteTime -lt $dtcorte }

        if (-not $alvos -or $alvos.Count -eq 0) {
            return "[$usuario][$navegador] Nada para limpar em: $wsPath"
        }

        foreach ($dir in $alvos) {
            try {
                Remove-Item -LiteralPath $dir.FullName -Recurse -Force -ErrorAction Stop
                Write-Output "[$usuario][$navegador] Apagado: $($dir.FullName) (ult.mod: $($dir.LastWriteTime))"
            } catch {
                # Sem encerrar processos: apenas logar falhas (locks)
                Write-Output "[$usuario][$navegador] Bloqueado/erro ao apagar $($dir.FullName): $($_.Exception.Message)"
            }
        }

        return "[$usuario][$navegador] Limpeza concluida (best-effort) em: $wsPath"
    }

    $jobs = @()
    foreach ($user in $userFolders) {
        foreach ($canal in $canais) {
            # perfis: Default + Profile *
            $base = Join-Path $user.FullName ("AppData\Local\{0}\User Data" -f $canal.Base)
            $perfis = @()
            if (Test-Path (Join-Path $base "Default")) { $perfis += "Default" }
            $perfis += (Get-ChildItem -Path $base -Directory -Filter "Profile *" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)

            foreach ($perfil in $perfis) {
                $wsPath = Join-Path (Join-Path $base $perfil) "WebStorage"
                if ($Paralelo) {
                    $jobs += Start-Job -ScriptBlock $sb -ArgumentList $wsPath, $user.Name, $canal.Nome, $cutoff
                } else {
                    $out = & $sb $wsPath $user.Name $canal.Nome $cutoff
                    if ($out) { Write-Log $out "INFO" }
                }
            }
        }
    }

    if ($Paralelo -and $jobs) {
        while ($jobs.State -contains 'Running') {
            foreach ($job in $jobs) {
                $o = Receive-Job -Job $job -Keep
                foreach ($l in $o) { if ($l) { Write-Host $l } }
            }
            Start-Sleep 1
        }
        foreach ($job in $jobs) {
            $o = Receive-Job -Job $job
            foreach ($l in $o) { if ($l) { Write-Host $l } }
        }
        $jobs | Remove-Job
    }

    Write-Log "Limpeza seletiva do WebStorage finalizada (sem encerrar processos)" "INFO"
}

# =================== NOVA FUNÇÃO v3.7.0: LIMPAR INDEXEDDB ===================

function Limpar-IndexedDB {
    <#
        .SYNOPSIS
            Remove dados antigos do IndexedDB (Chrome/Edge) mantendo apenas os mais recentes.
        .PARAMETER Dias
            Janela de retenção em dias (default = 30).
        .PARAMETER Paralelo
            Quando presente, processa caminhos em jobs paralelos.
    #>
    param(
        [int]$Dias = 30,
        [switch]$Paralelo
    )

    if ($Dias -lt 0) { $Dias = 0 }
    $cutoff = (Get-Date).AddDays(-$Dias)
    Write-Log "Iniciando limpeza seletiva do IndexedDB (mantendo ultimos $Dias dia(s))" "INFO"

    # Detectar processos abertos (não encerrar)
    $procs = "chrome","msedge","chrome.exe","msedge.exe"
    $emExec = Get-Process -ErrorAction SilentlyContinue | Where-Object { $procs -contains $_.Name }
    if ($emExec) {
        $lista = ($emExec | Select-Object -ExpandProperty Name | Sort-Object -Unique) -join ", "
        Write-Log "Navegadores em execucao detectados: $lista. Limpeza best-effort, itens bloqueados serao ignorados." "WARN"
    }

    # Canais a varrer
    $canais = @(
        @{ Nome = "Chrome";        Base = "Google\Chrome" }
        @{ Nome = "Chrome Beta";   Base = "Google\Chrome Beta" }
        @{ Nome = "Chrome Dev";    Base = "Google\Chrome Dev" }
        @{ Nome = "Chrome Canary"; Base = "Google\Chrome SxS" }
        @{ Nome = "Edge";          Base = "Microsoft\Edge" }
    )

    $userFolders = Get-ChildItem -Path "C:\Users" -Directory -ErrorAction SilentlyContinue

    $sb = {
    param($idbPath, $usuario, $navegador, $dtcorte)

    if (-not (Test-Path $idbPath)) { 
        return "[$usuario][$navegador] IndexedDB nao encontrado: $idbPath" 
    }

    $totalRemovido = 0
    $totalErros    = 0
    $espacoLiberado = 0

    # ── NOVA LÓGICA: apagar pastas-origem inteiras mais antigas que o corte ──
    # Cada pasta representa um site (ex: https_web.whatsapp.com_0.indexeddb.leveldb)
    $pastasOrigem = Get-ChildItem -LiteralPath $idbPath -Directory -ErrorAction SilentlyContinue |
                    Where-Object { $_.LastWriteTime -lt $dtcorte }

    foreach ($pasta in $pastasOrigem) {
        try {
            $tamanho = (Get-ChildItem -LiteralPath $pasta.FullName -Recurse -File -ErrorAction SilentlyContinue |
                        Measure-Object -Property Length -Sum).Sum
            Remove-Item -LiteralPath $pasta.FullName -Recurse -Force -ErrorAction Stop
            $totalRemovido++
            $espacoLiberado += $tamanho
            Write-Output "[$usuario][$navegador] Pasta removida: $($pasta.Name) (ult.mod: $($pasta.LastWriteTime))"
        } catch {
            $totalErros++
            Write-Output "[$usuario][$navegador] Bloqueado: $($pasta.Name) - $($_.Exception.Message)"
        }
    }

    # ── Fallback: arquivos avulsos antigos (caso existam fora das pastas-origem) ──
    $arquivos = Get-ChildItem -LiteralPath $idbPath -File -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -lt $dtcorte }

    foreach ($arq in $arquivos) {
        try {
            $tamanho = $arq.Length
            Remove-Item -LiteralPath $arq.FullName -Force -ErrorAction Stop
            $totalRemovido++
            $espacoLiberado += $tamanho
        } catch {
            $totalErros++
        }
    }

    $espacoMB = [math]::Round($espacoLiberado/1MB, 2)
    return "[$usuario][$navegador] IndexedDB: $totalRemovido item(ns) removido(s), $espacoMB MB liberados, $totalErros bloqueado(s)"
}

    $jobs = @()
    foreach ($user in $userFolders) {
        foreach ($canal in $canais) {
            $base = Join-Path $user.FullName ("AppData\Local\{0}\User Data" -f $canal.Base)
            
            # Processar perfis: Default + Profile *
            $perfis = @()
            if (Test-Path (Join-Path $base "Default")) { $perfis += "Default" }
            $perfis += (Get-ChildItem -Path $base -Directory -Filter "Profile *" -ErrorAction SilentlyContinue | 
                        Select-Object -ExpandProperty Name)

            foreach ($perfil in $perfis) {
                $idbPath = Join-Path (Join-Path $base $perfil) "IndexedDB"
                
                if ($Paralelo) {
                    $jobs += Start-Job -ScriptBlock $sb -ArgumentList $idbPath, $user.Name, $canal.Nome, $cutoff
                } else {
                    $out = & $sb $idbPath $user.Name $canal.Nome $cutoff
                    if ($out) { 
                        foreach ($linha in $out) { Write-Log $linha "INFO" }
                    }
                }
            }
        }
    }

    if ($Paralelo -and $jobs) {
        while ($jobs.State -contains 'Running') {
            foreach ($job in $jobs) {
                $o = Receive-Job -Job $job -Keep
                foreach ($l in $o) { if ($l) { Write-Host $l } }
            }
            Start-Sleep 1
        }
        foreach ($job in $jobs) {
            $o = Receive-Job -Job $job
            foreach ($l in $o) { if ($l) { Write-Host $l } }
        }
        $jobs | Remove-Job
    }

    Write-Log "Limpeza do IndexedDB finalizada (sem encerrar processos)" "INFO"
}

# =================== FUNÇÕES DE LIMPEZA ===================

function Limpar-Adobe {
    param (
        [string]$caminhoAdobe,
        [int]$DiasCorte = 30
    )
    if (-not (Test-Path $caminhoAdobe)) {
        return
    }
    Write-Log "Iniciando limpeza da pasta Adobe: $caminhoAdobe" "INFO"

    $dataLimite = (Get-Date).AddDays(-$DiasCorte)

    $arquivos = Get-ChildItem -Path $caminhoAdobe -File -Recurse -ErrorAction SilentlyContinue
    foreach ($arquivo in $arquivos) {
        if ($arquivo.LastWriteTime -lt $dataLimite) {
            try {
                Remove-Item -Path $arquivo.FullName -Force -ErrorAction Stop
                Write-Log "Arquivo excluido: $($arquivo.FullName)" "INFO"
            }
            catch {
                Write-Log "Erro ao excluir arquivo: $($arquivo.FullName) - $_" "WARN"
            }
        }
    }

    $pastas = Get-ChildItem -Path $caminhoAdobe -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -Skip 1
    foreach ($pasta in $pastas) {
        try {
            $conteudo = Get-ChildItem -Path $pasta.FullName -Recurse -File -ErrorAction SilentlyContinue
            if ($conteudo.Count -eq 0) {
                Remove-Item -Path $pasta.FullName -Recurse -Force -ErrorAction Stop
                Write-Log "Pasta vazia excluida: $($pasta.FullName)" "INFO"
            }
        }
        catch {
            Write-Log "Erro ao excluir pasta: $($pasta.FullName) - $_" "WARN"
        }
    }
}

function Limpar-CachesBrowsers {
    param (
        [array]$caminhos
    )
    Write-Log "Iniciando limpeza de caches dos navegadores" "INFO"
    foreach ($path in $caminhos) {
        try {
            $items = Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue
            foreach ($item in $items) {
                try {
                    Remove-Item -Path $item.FullName -Recurse -Force -ErrorAction Stop
                    Write-Log "Cache excluido: $($item.FullName)" "INFO"
                }
                catch {
                    Write-Log "Erro ao excluir cache: $($item.FullName) - $_" "WARN"
                }
            }
        }
        catch {
            Write-Log "Erro ao acessar caminho de cache: $path - $_" "WARN"
        }
    }
}

function Limpar-PastaJob {
    param (
        [string]$caminho
    )
    if (Test-Path $caminho) {
        Write-Output "Iniciando limpeza: $caminho"
        try {
            $itens = Get-ChildItem -Path $caminho -Force -ErrorAction SilentlyContinue
            foreach ($item in $itens) {
                try {
                    Remove-Item -Path $item.FullName -Recurse -Force -ErrorAction Stop
                    Write-Output "Excluido: $($item.FullName)"
                }
                catch {
                    Write-Output "Erro ao excluir item: $($item.FullName) - $_"
                }
            }
            Write-Output "Limpeza concluida: $caminho"
        }
        catch {
            Write-Output "Erro ao listar itens em: $caminho - $_"
        }
    }
}

function Limpar-TemporariosEdownloads {
    param (
        [array]$pastasRelativas,
        [array]$pastasAbsolutas,
        [array]$pastasSistema,
        [int]$diasDownloads,
        [array]$naoExcluirDownloads
    )
    Write-Log "Iniciando limpeza de arquivos temporarios e Downloads" "INFO"

    $userFolders = Get-ChildItem -Path "C:\Users" -Directory -ErrorAction SilentlyContinue

    # Criar jobs para limpar pastas relativas de cada usuário
    $jobs = @()
    foreach ($userFolder in $userFolders) {
        foreach ($folder in $pastasRelativas) {
            $fullPath = Join-Path $userFolder.FullName $folder
            $jobs += Start-Job -ScriptBlock ${function:Limpar-PastaJob} -ArgumentList $fullPath
        }
    }

    # Criar jobs para limpar pastas absolutas (wildcards expandidos manualmente)
    foreach ($pattern in $pastasAbsolutas) {
        $resolved = Get-Item -Path $pattern -ErrorAction SilentlyContinue
        foreach ($item in $resolved) {
            $jobs += Start-Job -ScriptBlock ${function:Limpar-PastaJob} -ArgumentList $item.FullName
        }
    }

    # Criar jobs para limpar pastas do sistema
    foreach ($folder in $pastasSistema) {
        $jobs += Start-Job -ScriptBlock ${function:Limpar-PastaJob} -ArgumentList $folder
    }

    # Monitorar e exibir progresso dos jobs sem duplicar linhas
    $printed = @{}
    while ($jobs.State -contains 'Running') {
        foreach ($job in $jobs) {
            $output = Receive-Job -Job $job -Keep
            $already = $printed[$job.Id]
            $new = if ($already) { $output | Select-Object -Skip $already } else { $output }
            foreach ($linha in $new) { Write-Host $linha }
            $printed[$job.Id] = $output.Count
        }
        Start-Sleep -Seconds 1
    }

    # Receber mensagens finais dos jobs
    foreach ($job in $jobs) {
        $output = Receive-Job -Job $job
        foreach ($linha in $output) {
            Write-Host $linha
        }
    }

    # Remover jobs
    $jobs | Remove-Job

    # Limpeza dos arquivos antigos na pasta Downloads (sequencial)
    $downloadsPaths = $userFolders | ForEach-Object { Join-Path $_.FullName "Downloads" }
    foreach ($downloadsPath in $downloadsPaths) {
        if (Test-Path $downloadsPath) {
            $arquivosDownloads = Get-ChildItem -Path $downloadsPath -Force -ErrorAction SilentlyContinue | Where-Object {
                $_.LastWriteTime -lt (Get-Date).AddDays(-$diasDownloads) -and
                ($naoExcluirDownloads -notcontains $_.Name)
            }
            foreach ($arquivo in $arquivosDownloads) {
                try {
                    Remove-Item -Path $arquivo.FullName -Recurse -Force -ErrorAction Stop
                    Write-Log "Arquivo antigo excluido: $($arquivo.FullName)" "INFO"
                }
                catch {
                    Write-Log "Erro ao excluir arquivo: $($arquivo.FullName) - $_" "WARN"
                }
            }
        }
    }
    Write-Log "Limpeza de arquivos antigos na pasta Downloads concluida" "INFO"
}

function Limpar-Insomnia {
    Write-Log "Iniciando limpeza de versoes antigas do Insomnia" "INFO"

    $userFolders = Get-ChildItem -Path "C:\Users" -Directory -ErrorAction SilentlyContinue

    foreach ($userFolder in $userFolders) {
        $insomniaPath = Join-Path $userFolder.FullName "AppData\Local\insomnia"
        if (-not (Test-Path $insomniaPath)) {
            continue
        }

        $versoes = Get-ChildItem -Path $insomniaPath -Directory -ErrorAction SilentlyContinue |
                   Where-Object { $_.Name -like "app-*" } |
                   Sort-Object Name -Descending

        if ($versoes.Count -le 1) {
            continue
        }

        $maisRecente = $versoes[0].Name
        Write-Log "Mantendo versao mais recente: $maisRecente para o usuario $($userFolder.Name)" "INFO"

        foreach ($versao in $versoes | Select-Object -Skip 1) {
            try {
                Remove-Item -Path $versao.FullName -Recurse -Force -ErrorAction Stop
                Write-Log "Versao antiga removida: $($versao.FullName)" "INFO"
            }
            catch {
                Write-Log "Erro ao remover versao: $($versao.FullName) - $_" "WARN"
            }
        }
    }
}

# =================== BLOCO PRINCIPAL ===================

try {
    $script:ScriptStartTime = Get-Date
    Write-Banner
    Write-Log "========================================" "INFO"
    Write-Log "Script de Limpeza de Sistema v$SCRIPT_VERSION" "INFO"
    Write-Log "========================================" "INFO"

    if ($limparNuGetCache -eq "sim") {
        Write-Phase "Cache NuGet"
        Limpar-NuGetCaches -Paralelo
        Add-CleanResult -Categoria "NuGet" -Alvo "Cache global" -Status "OK"
    }
    if ($limparNpmCache -eq "sim") {
        Write-Phase "Cache npm"
        Limpar-NpmCache -Paralelo
        Add-CleanResult -Categoria "npm" -Alvo "Cache por perfil" -Status "OK"
    }

    Write-Phase "Snapshots Chrome/Edge"
    Limpar-ChromeSnapshots -Manter $manterSnapshots -Paralelo
    Add-CleanResult -Categoria "Chrome/Edge" -Alvo "Snapshots" -Status "OK" -Obs "manter $manterSnapshots"

    if ($limparWebStorage -eq "sim") {
        Write-Phase "WebStorage Chrome/Edge"
        Limpar-WebStorageSeletivo -Dias $diasWebStorage -Paralelo
        Add-CleanResult -Categoria "Chrome/Edge" -Alvo "WebStorage" -Status "OK" -Obs "$diasWebStorage dia(s)"
    }

    if ($limparIndexedDB -eq "sim") {
        Write-Phase "IndexedDB Chrome/Edge"
        Limpar-IndexedDB -Dias $diasIndexedDB -Paralelo
        Add-CleanResult -Categoria "Chrome/Edge" -Alvo "IndexedDB" -Status "OK" -Obs "$diasIndexedDB dia(s)"
    }

    Write-Phase "Aplicativos e caches locais"
    Limpar-Insomnia
    Add-CleanResult -Categoria "Insomnia" -Alvo "Versoes antigas" -Status "OK"

    Write-Phase "Adobe e navegadores"
    Limpar-Adobe -caminhoAdobe "C:\ProgramData\Adobe\ARM" -DiasCorte $dataDeCorteAdobe
    Add-CleanResult -Categoria "Adobe" -Alvo "ARM" -Status "OK" -Obs "$dataDeCorteAdobe dia(s)"
    Limpar-CachesBrowsers -caminhos $caminhosBrowsers
    Add-CleanResult -Categoria "Navegadores" -Alvo "Caches" -Status "OK"

    Write-Phase "Temporarios e Downloads"
    Limpar-TemporariosEdownloads -pastasRelativas $pastasRelativas `
                                 -pastasAbsolutas $pastasAbsolutas `
                                 -pastasSistema $pastasSistema `
                                 -diasDownloads $diasDownloads `
                                 -naoExcluirDownloads $naoExcluirDownloads
    Add-CleanResult -Categoria "Sistema" -Alvo "Temp/Downloads" -Status "OK" -Obs "$diasDownloads dia(s)"

    Show-Summary
    Write-Log "========================================" "INFO"
    Write-Log "Limpeza concluida com sucesso!" "INFO"
    Write-Log "========================================" "INFO"
    Wait-Final
}
catch {
    Add-CleanResult -Categoria "Geral" -Alvo "Execucao" -Status "FALHOU" -Obs $_.Exception.Message
    Show-Summary
    Write-Log "Erro inesperado durante a execucao do script: $_" "ERROR"
    Wait-Final
    throw
}
