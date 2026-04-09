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
    Última modif: 2025-02-12
    Versão      : 3.7.0
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
    3.7.0 – 12/02/2025 – NOVO: Limpar-IndexedDB (Chrome/Edge) + variáveis $limparIndexedDB e $diasIndexedDB.
#>

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

# Pastas comuns dentro dos perfis de usuários que devem ser limpas
$pastasComuns = @(
    "AppData\Local\Microsoft\Terminal Server Client\Cache\",
    "AppData\Local\Microsoft\Windows\Explorer\",
    "AppData\Local\Microsoft\Windows\INetCache\",
    "AppData\Local\Yarn\Cache\v6\",
    "AppData\Roaming\Code\Cache\",
    "AppData\Roaming\Code\CachedData\",
    "AppData\Roaming\Code\CachedExtensionVSIXs\",
    "AppData\Local\Temp\",

    # Teams
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
        Write-Host "O script precisa ser executado como Administrador. Solicitando elevação..."
        Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        exit
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
    # Aqui pode ser implementado registro em arquivo de log, se necessário
}

# =================== FUNÇÃO: MANTER APENAS N SNAPSHOTS (CHROME/EDGE) ===================

function Limpar-ChromeSnapshots {
    <#
        .SYNOPSIS
            Mantém apenas N snapshots mais recentes do Chrome/Edge por usuário e canal.
        .PARAMETER Manter
            Quantidade de snapshots a manter (default = 1).
        .PARAMETER Paralelo
            Quando presente, executa em jobs paralelos.
    #>
    param(
        [int]$Manter = 1,
        [switch]$Paralelo
    )

    if ($Manter -lt 0) { $Manter = 0 }

    Write-Log "Iniciando limpeza de Snapshots (manter = $Manter)" "INFO"

    $canais = @(
        @{ Nome = "Chrome";        Base = "Google\Chrome" }
        @{ Nome = "Chrome Beta";   Base = "Google\Chrome Beta" }
        @{ Nome = "Chrome Dev";    Base = "Google\Chrome Dev" }
        @{ Nome = "Chrome Canary"; Base = "Google\Chrome SxS" }
        @{ Nome = "Edge";          Base = "Microsoft\Edge" }
    )

    $userFolders = Get-ChildItem -Path "C:\Users" -Directory -ErrorAction SilentlyContinue
    $jobs = @()

    $sb = {
        param($snapPath, $manter, $canal, $usuario)

        try {
            if (-not (Test-Path $snapPath)) {
                Write-Output "[$usuario][$canal] Pasta nao encontrada: $snapPath"
                return
            }

            # Pastas de snapshot ordenadas do mais novo para o mais antigo
            $dirs = Get-ChildItem -Path $snapPath -Directory -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending

            if (-not $dirs -or $dirs.Count -le $manter) {
                Write-Output "[$usuario][$canal] Nada para excluir (pastas: $($dirs.Count))"
                return
            }

            $keep = $dirs | Select-Object -First $manter
            $del  = $dirs | Select-Object -Skip $manter

            foreach ($d in $del) {
                try {
                    Remove-Item -LiteralPath $d.FullName -Recurse -Force -ErrorAction Stop
                    Write-Output "[$usuario][$canal] Excluido snapshot: $($d.Name)"
                } catch {
                    Write-Output "[$usuario][$canal] Falha ao excluir $($d.FullName): $($_.Exception.Message)"
                }
            }

            $keptNames = ($keep | ForEach-Object Name) -join ', '
            Write-Output "[$usuario][$canal] Mantido(s): $keptNames"
        }
        catch {
            Write-Output "[$usuario][$canal] Erro ao processar $snapPath — $($_.Exception.Message)"
        }
    }

    foreach ($user in $userFolders) {
        foreach ($canal in $canais) {
            $snapPath = Join-Path $user.FullName ("AppData\Local\{0}\User Data\Snapshots" -f $canal.Base)
            if ($Paralelo) {
                $jobs += Start-Job -ScriptBlock $sb -ArgumentList $snapPath, $Manter, $canal.Nome, $user.Name
            } else {
                $out = & $sb $snapPath $Manter $canal.Nome $user.Name
                foreach ($line in $out) { Write-Log $line "INFO" }
            }
        }
    }

    if ($Paralelo -and $jobs) {
        while ($jobs.State -contains 'Running') {
            foreach ($job in $jobs) {
                $out = Receive-Job -Job $job -Keep
                foreach ($line in $out) { Write-Host $line }
            }
            Start-Sleep 1
        }
        foreach ($job in $jobs) {
            $out = Receive-Job -Job $job
            foreach ($line in $out) { Write-Host $line }
        }
        $jobs | Remove-Job
    }

    Write-Log "Limpeza de Snapshots do Chrome/Edge finalizada" "INFO"
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
        $jobs | Remove-Job
    }

    Write-Log "Limpeza do cache NuGet finalizada" "INFO"
}

# =================== FUNÇÃO: LIMPAR NPM CACHE (sem encerrar processos) ===================

function Limpar-NpmCache {
    param([switch]$Paralelo)

    Write-Log "Iniciando limpeza do npm-cache em todos os perfis (sem encerrar processos)" "INFO"

    $npmExe = (Get-Command npm -ErrorAction SilentlyContinue).Source   # global npm
    if (-not $npmExe) {
        Write-Log "npm.exe nao encontrado no PATH; farei so a limpeza fisica." "WARN"
    }

    $userFolders = Get-ChildItem 'C:\Users' -Directory -ErrorAction SilentlyContinue

    # 1) LIMPAR CONTEÚDO — pode ser em paralelo
    $cleanJobs = @()
    $cleanSB   = {
        param($cache)

        if (-not (Test-Path $cache)) {
            New-Item -ItemType Directory -Path $cache -Force | Out-Null
        }

        # Ajusta permissões, mas não encerra processos
        icacls $cache /grant "*S-1-5-32-544:(OI)(CI)(F)" /T /C | Out-Null

        try {
            Get-ChildItem -LiteralPath $cache -Recurse -Force -ErrorAction SilentlyContinue `
                | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        } catch {
            Write-Output "Falha ao limpar $cache (possivel lock): $($_.Exception.Message)"
        }
    }

    foreach ($u in $userFolders) {
        foreach ($c in @(
            (Join-Path $u.FullName 'AppData\Local\npm-cache'),
            (Join-Path $u.FullName 'AppData\Roaming\npm-cache')
        )) {
            if ($Paralelo) {
                $cleanJobs += Start-Job -ScriptBlock $cleanSB -ArgumentList $c
            } else {
                & $cleanSB $c
            }
        }
    }

    if ($Paralelo -and $cleanJobs) {
        $cleanJobs | Wait-Job | Out-Null
        $cleanJobs | Remove-Job
    }

    # 2) VERIFICAR E RECONSTRUIR — sem encerrar nada
    if ($npmExe) {
        foreach ($u in $userFolders) {
            foreach ($c in @(
                (Join-Path $u.FullName 'AppData\Local\npm-cache'),
                (Join-Path $u.FullName 'AppData\Roaming\npm-cache')
            )) {
                if (-not (Test-Path $c)) { continue }

                try {
                    & $npmExe cache verify --cache "$c" --silent *> $null
                    if ($LASTEXITCODE -ne 0) {
                        Write-Log "npm verify retornou codigo $LASTEXITCODE em $c (possivel lock). Continuacao sem erro fatal." "WARN"
                    }
                }
                catch {
                    Write-Log "Erro no npm verify para $c — $($_.Exception.Message)" "WARN"
                }
            }
        }
    }

    Write-Log "Limpeza e verificacao do npm-cache concluidas (best-effort, sem encerrar processos)" "INFO"
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
        [string]$caminhoAdobe
    )
    if (-not (Test-Path $caminhoAdobe)) {
        return
    }
    Write-Log "Iniciando limpeza da pasta Adobe: $caminhoAdobe" "INFO"

    $dataLimite = (Get-Date).AddDays(-$dataDeCorteAdobe)

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
        [array]$pastasComuns,
        [array]$pastasSistema,
        [int]$diasDownloads,
        [array]$naoExcluirDownloads
    )
    Write-Log "Iniciando limpeza de arquivos temporarios e Downloads" "INFO"

    $userFolders = Get-ChildItem -Path "C:\Users" -Directory -ErrorAction SilentlyContinue

    # Criar jobs para limpar pastas comuns de cada usuário
    $jobs = @()
    foreach ($userFolder in $userFolders) {
        foreach ($folder in $pastasComuns) {
            $fullPath = Join-Path $userFolder.FullName $folder
            $jobs += Start-Job -ScriptBlock ${function:Limpar-PastaJob} -ArgumentList $fullPath
        }
    }

    # Criar jobs para limpar pastas do sistema
    foreach ($folder in $pastasSistema) {
        $jobs += Start-Job -ScriptBlock ${function:Limpar-PastaJob} -ArgumentList $folder
    }

    # Monitorar e exibir progresso dos jobs em tempo real
    while ($jobs.State -contains 'Running') {
        foreach ($job in $jobs) {
            $output = Receive-Job -Job $job -Keep
            foreach ($linha in $output) {
                Write-Host $linha
            }
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
    Write-Log "========================================" "INFO"
    Write-Log "Script de Limpeza de Sistema v3.7.0" "INFO"
    Write-Log "========================================" "INFO"
    
    if ($limparNuGetCache -eq "sim") { Limpar-NuGetCaches -Paralelo }
    if ($limparNpmCache  -eq "sim") { Limpar-NpmCache -Paralelo }

    # Manter só N snapshots mais recentes por canal (Chrome/Edge)
    Limpar-ChromeSnapshots -Manter $manterSnapshots -Paralelo

    # Manter WebStorage apenas dos últimos N dias (sem encerrar processos)
    if ($limparWebStorage -eq "sim") {
        Limpar-WebStorageSeletivo -Dias $diasWebStorage -Paralelo
    }

    # NOVO v3.7.0: Manter IndexedDB apenas dos últimos N dias (sem encerrar processos)
    if ($limparIndexedDB -eq "sim") {
        Limpar-IndexedDB -Dias $diasIndexedDB -Paralelo
    }

    Limpar-Insomnia
    Limpar-Adobe -caminhoAdobe "C:\ProgramData\Adobe\ARM"
    Limpar-CachesBrowsers -caminhos $caminhosBrowsers
    Limpar-TemporariosEdownloads -pastasComuns $pastasComuns `
                                 -pastasSistema $pastasSistema `
                                 -diasDownloads $diasDownloads `
                                 -naoExcluirDownloads $naoExcluirDownloads

    Write-Log "========================================" "INFO"
    Write-Log "Limpeza concluida com sucesso!" "INFO"
    Write-Log "========================================" "INFO"
}
catch {
    Write-Log "Erro inesperado durante a execucao do script: $_" "ERROR"
    throw
}