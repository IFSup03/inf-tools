$ErrorActionPreference = "Continue"

# ----------------------------------------------------------
# Versao e Historico de Atualizacoes
# ----------------------------------------------------------
$SCRIPT_VERSION = "2.5.0"
$SCRIPT_DATA    = "09/04/2026"
$CHANGELOG = @(
    [PSCustomObject]@{ Versao = "2.1.0"; Data = "09/04/2026"; Descricao = "Corrigido bug C:\Program1: /DIR do Git Bash agora usa aspas para caminhos com espacos" },
    [PSCustomObject]@{ Versao = "2.1.0"; Data = "09/04/2026"; Descricao = "Melhorada deteccao do Git: busca em mais caminhos e no registro do Windows" },
    [PSCustomObject]@{ Versao = "2.1.0"; Data = "09/04/2026"; Descricao = "Auto-elevacao compativel com execucao via irm | iex (GitHub) e arquivo local" },
    [PSCustomObject]@{ Versao = "2.1.0"; Data = "09/04/2026"; Descricao = "Corrigido erro de sintaxe PS5: operador ?. substituido por compativel com PS5" },
    [PSCustomObject]@{ Versao = "2.0.0"; Data = "08/04/2026"; Descricao = "Menu principal com opcoes Instalar e Remover" },
    [PSCustomObject]@{ Versao = "2.0.0"; Data = "08/04/2026"; Descricao = "Adicionado OpenCode Desktop (SST.OpenCodeDesktop via winget)" },
    [PSCustomObject]@{ Versao = "2.0.0"; Data = "08/04/2026"; Descricao = "Deteccao automatica de ambiente servidor (ProductType) para Claude Code" },
    [PSCustomObject]@{ Versao = "2.0.0"; Data = "08/04/2026"; Descricao = "Claude Code instalado via npm em servidores/VMs (evita crash do Bun sem AVX)" },
    [PSCustomObject]@{ Versao = "2.0.0"; Data = "08/04/2026"; Descricao = "Node.js instalado com ALLUSERS=1 (disponivel para todos os usuarios)" },
    [PSCustomObject]@{ Versao = "2.0.0"; Data = "08/04/2026"; Descricao = "PATH corrigido: adiciona %APPDATA%\npm e %ProgramFiles%\nodejs automaticamente" },
    [PSCustomObject]@{ Versao = "2.0.0"; Data = "08/04/2026"; Descricao = "Deteccao de instalacao via winget list (mais confiavel que winget upgrade)" },
    [PSCustomObject]@{ Versao = "2.0.0"; Data = "08/04/2026"; Descricao = "Mensagens de Desktop corrigidas: instrui pesquisar no Menu Iniciar" },
    [PSCustomObject]@{ Versao = "2.0.0"; Data = "08/04/2026"; Descricao = "Auto-elevacao: script se reinicia como Administrador se necessario" },
    [PSCustomObject]@{ Versao = "2.0.0"; Data = "08/04/2026"; Descricao = "Mensagem final diferenciada: CLI vs Desktop vs ambos" },
    [PSCustomObject]@{ Versao = "1.0.0"; Data = "07/04/2026"; Descricao = "Versao inicial: Claude Code, Codex CLI, OpenCode, Claude Desktop, Codex Desktop" },
    [PSCustomObject]@{ Versao = "1.0.0"; Data = "07/04/2026"; Descricao = "Instalacao silenciosa via winget com fallback por download direto" },
    [PSCustomObject]@{ Versao = "1.0.0"; Data = "07/04/2026"; Descricao = "Verificacao e atualizacao automatica de versoes instaladas" },
    [PSCustomObject]@{ Versao = "1.0.0"; Data = "07/04/2026"; Descricao = "Suporte a Git Bash como pre-requisito do Claude Code" }
)

# Garante que a janela nunca feche sozinha
try {


# ----------------------------------------------------------
# Encoding: troca UTF-8 e habilita sequencias ANSI/VT no terminal
# ----------------------------------------------------------
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

try {
    $sig = @"
        [DllImport("kernel32.dll", SetLastError=true)]
        public static extern IntPtr GetStdHandle(int nStdHandle);
        [DllImport("kernel32.dll", SetLastError=true)]
        public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
        [DllImport("kernel32.dll", SetLastError=true)]
        public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
"@
    $k32    = Add-Type -MemberDefinition $sig -Name "K32VT" -Namespace "Win32" -PassThru
    $handle = [Win32.K32VT]::GetStdHandle(-11)
    $mode   = 0
    [Win32.K32VT]::GetConsoleMode($handle, [ref]$mode) | Out-Null
    [Win32.K32VT]::SetConsoleMode($handle, ($mode -bor 0x0004)) | Out-Null
} catch { <# silencioso se nao suportado #> }

# --- Cores para output ---
function Write-Step  { param($msg) Write-Host "`n[>>] $msg" -ForegroundColor Cyan }
function Write-Ok    { param($msg) Write-Host "[ OK] $msg" -ForegroundColor Green }
function Write-Warn  { param($msg) Write-Host "[AVS] $msg" -ForegroundColor Yellow }
function Write-Fail  { param($msg) Write-Host "[ERR] $msg" -ForegroundColor Red }

# --- Pausa legivel entre etapas (segundos) ---
function Pause-Readable { param([int]$Seconds = 3) Start-Sleep -Seconds $Seconds }

# --- Confirmacao por tecla: ENTER = sim, ESC = nao ---
# Retorna $true para ENTER, $false para ESC
function Confirm-Tecla {
    param([string]$Mensagem)
    Write-Host "  $Mensagem [ENTER = sim | ESC = nao] " -ForegroundColor White -NoNewline
    while ($true) {
        $key = [Console]::ReadKey($true)
        if ($key.Key -eq 'Enter') {
            Write-Host "Sim" -ForegroundColor Green
            return $true
        }
        if ($key.Key -eq 'Escape') {
            Write-Host "Nao" -ForegroundColor Gray
            return $false
        }
    }
}

# --- Verifica suporte AVX no processador ---
function Test-AVXSupport {
    try {
        $cpu = Get-WmiObject -Class Win32_Processor | Select-Object -First 1
        # Tenta detectar AVX via registros do processador
        $avxTest = [System.Runtime.Intrinsics.X86.Avx]::IsSupported
        return $avxTest
    } catch {
        return $false
    }
}

# --- Instala Node.js para todo o sistema (ALLUSERS=1) ---
function Install-NodeJS {
    param([bool]$WingetOk)

    $nodeInstalled = $false

    # Tenta via winget primeiro (mais confiavel)
    if ($WingetOk) {
        try {
            Write-Step "Instalando Node.js LTS via winget..."
            & winget install --id OpenJS.NodeJS.LTS --silent --scope machine `
                --accept-package-agreements --accept-source-agreements 2>&1 |
                Where-Object { $_ -notmatch '^\s*[-\\|/]\s*$' } |
                ForEach-Object { if ($_.Trim()) { Write-Host $_ } }
            $nodeInstalled = $true
        } catch {
            Write-Warn "winget falhou. Tentando download direto..."
        }
    }

    # Fallback: download direto do MSI com ALLUSERS=1
    if (-not $nodeInstalled) {
        try {
            Write-Step "Baixando instalador do Node.js LTS..."
            $nodeInfo    = Invoke-RestMethod "https://nodejs.org/dist/index.json"
            $lts         = $nodeInfo | Where-Object { $_.lts } | Select-Object -First 1
            $nodeVersion = $lts.version
            $nodeUrl     = "https://nodejs.org/dist/$nodeVersion/node-$nodeVersion-x64.msi"
            $nodeMsi     = "$env:TEMP\node-lts.msi"
            Invoke-WebRequest -Uri $nodeUrl -OutFile $nodeMsi -UseBasicParsing
            Write-Step "Instalando Node.js $nodeVersion para todos os usuarios..."
            # ALLUSERS=1 garante instalacao para todo o sistema, nao so o usuario atual
            Start-Process msiexec.exe -ArgumentList "/i `"$nodeMsi`" /quiet /norestart ALLUSERS=1" -Wait
            Remove-Item $nodeMsi -Force -ErrorAction SilentlyContinue
            $nodeInstalled = $true
        } catch {
            Write-Fail "Falha ao instalar Node.js: $_"
        }
    }

    if ($nodeInstalled) {
        # Atualiza PATH da sessao para encontrar o npm recem instalado
        $nodePaths = @(
            "$env:ProgramFiles\nodejs",
            "${env:ProgramFiles(x86)}\nodejs",
            "$env:APPDATA\npm"
        )
        foreach ($p in $nodePaths) {
            if ((Test-Path $p) -and ($env:Path -notlike "*$p*")) {
                $env:Path = "$p;$env:Path"
            }
        }

        # Verifica se npm esta disponivel agora
        $npmOk = $false
        try { $null = & npm --version 2>&1; $npmOk = $true } catch { }

        if ($npmOk) {
            Write-Ok "Node.js instalado com sucesso."
            return $true
        } else {
            Write-Warn "Node.js instalado. Feche e reabra o terminal e execute o script novamente."
            return $false
        }
    }

    return $false
}

# --- Garante que Node.js/npm esta disponivel, instalando se necessario ---
function Ensure-NodeJS {
    param([bool]$WingetOk)

    # Atualiza PATH da sessao para caminhos padrao do Node
    $nodePaths = @(
        "$env:ProgramFiles\nodejs",
        "${env:ProgramFiles(x86)}\nodejs",
        "$env:APPDATA\npm"
    )
    foreach ($p in $nodePaths) {
        if ((Test-Path $p) -and ($env:Path -notlike "*$p*")) {
            $env:Path = "$p;$env:Path"
        }
    }

    # Verifica se npm ja esta disponivel
    $npmOk = $false
    try { $null = & npm --version 2>&1; $npmOk = $true } catch { }

    if ($npmOk) {
        return $true
    }

    # npm nao encontrado — instalar Node.js
    Write-Warn "Node.js/npm nao encontrado. Instalando automaticamente..."
    return (Install-NodeJS -WingetOk $WingetOk)
}

# --- Verifica e corrige o PATH para ferramentas CLI ---
function Test-And-Fix-Path {
    $caminhos = @(
        "$env:APPDATA\npm",
        "$env:ProgramFiles\nodejs",
        "${env:ProgramFiles(x86)}\nodejs",
        "$env:USERPROFILE\.local\bin"
    )

    $pathUsuario  = [Environment]::GetEnvironmentVariable("Path", "User")
    $pathMaquina  = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $pathCompleto = "$pathMaquina;$pathUsuario"
    $atualizado   = $false
    $problemas    = @()
    $corrigidos   = @()

    foreach ($dir in $caminhos) {
        if (-not (Test-Path $dir)) { continue }  # Ignora pastas que nao existem

        $noPath = ($pathCompleto -split ";") -notcontains $dir
        if ($noPath) {
            $problemas += $dir
            # Adiciona ao PATH do usuario
            $pathUsuario = ($pathUsuario.TrimEnd(";") + ";$dir").TrimStart(";")
            $atualizado  = $true
            $corrigidos += $dir
        }

        # Garante na sessao atual tambem
        if ($env:Path -notlike "*$dir*") {
            $env:Path = "$dir;$env:Path"
        }
    }

    if ($atualizado) {
        [Environment]::SetEnvironmentVariable("Path", $pathUsuario, "User")
        Write-Warn "PATH incompleto. Entradas adicionadas:"
        foreach ($c in $corrigidos) { Write-Ok "  + $c" }
        Write-Warn "Abra um novo terminal para que as alteracoes tenham efeito."
    } else {
        Write-Ok "PATH configurado corretamente."
    }

    return $problemas.Count -eq 0
}

# --- Verifica/instala/atualiza pacote npm global ---
function Invoke-NpmTool {
    param(
        [string]$Label,      # Nome amigavel exibido
        [string]$Cmd,        # Comando de terminal (ex: opencode, codex)
        [string]$Package,    # Nome do pacote npm (ex: opencode-ai)
        [string]$NpmName     # Mesmo que Package (usado na URL do registry)
    )

    Write-Step "Verificando $Label..."

    # Garante Node.js/npm instalado para todo o sistema
    if (-not (Ensure-NodeJS -WingetOk $wingetOk)) {
        Write-Warn "Nao foi possivel garantir o Node.js. Pulando $Label."
        Pause-Readable 3
        return
    }

    $installed = $false
    $currentVer = $null
    try {
        $out = & $Cmd --version 2>&1
        $currentVer = ($out | Out-String).Trim()
        $installed = $true
    } catch { $installed = $false }

    if ($installed) {
        Write-Ok "$Label ja instalado. Versao atual: $currentVer"
        Write-Step "Verificando atualizacoes do $Label..."
        try {
            $info       = Invoke-RestMethod "https://registry.npmjs.org/$NpmName/latest"
            $latestVer  = $info.version
            $installedV = ($currentVer -replace '^[^\d]*').Trim() -split '\s+' | Select-Object -First 1

            Write-Ok "Versao instalada   : $installedV"
            Write-Ok "Versao mais recente: $latestVer"

            if ($installedV -eq $latestVer) {
                Write-Ok "$Label esta atualizado. Nenhuma acao necessaria."
                Pause-Readable 3
            } else {
                Write-Warn "Atualizacao disponivel: $installedV -> $latestVer"
                Pause-Readable 2
                Write-Step "Atualizando $Label via npm..."
                & npm install -g $Package 2>&1 | ForEach-Object { Write-Host $_ }
                Write-Ok "$Label atualizado com sucesso."
                Pause-Readable 3
            }
        } catch {
            Write-Warn "Nao foi possivel verificar atualizacoes do ${Label}: $_"
            Pause-Readable 3
        }
    } else {
        Write-Step "$Label nao encontrado. Iniciando instalacao via npm..."
        try {
            & npm install -g $Package 2>&1 | ForEach-Object { Write-Host $_ }
            Write-Ok "$Label instalado com sucesso."
            Write-Warn "Abra um novo terminal para usar o comando '$Cmd'."
            Pause-Readable 3
        } catch {
            Write-Fail "Falha na instalacao do ${Label}: $_"
            Pause-Readable 3
        }
    }
}

# ----------------------------------------------------------
# FUNCAO DE DIAGNOSTICO - verifica estado de cada ferramenta
# Parametros: flags booleanas indicando quais ferramentas verificar
# Retorna: $true se pode prosseguir, $false se usuario cancelou
# ----------------------------------------------------------
function Invoke-Diagnostico {
    param(
        [bool]$CheckGit        = $false,
        [bool]$CheckClaudeCLI  = $false,
        [bool]$CheckCodexCLI   = $false,
        [bool]$CheckOpenCode   = $false,
        [bool]$CheckClaudeDesk = $false,
        [bool]$CheckCodexDesk  = $false,
        [bool]$CheckOpenDesk   = $false
    )

    Clear-Host
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "   Diagnostico do Ambiente" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Verificando ferramentas selecionadas..." -ForegroundColor DarkGray
    Write-Host ""

    # Garante caminhos npm/node no PATH para deteccao
    $nodePaths = @("$env:ProgramFiles\nodejs", "$env:APPDATA\npm")
    foreach ($p in $nodePaths) {
        $pExists = Test-Path -LiteralPath $p -ErrorAction SilentlyContinue
        if ($pExists -and ($env:Path -split ";" | Where-Object { $_ -ieq $p }) -eq $null) {
            $env:Path = "$p;$env:Path"
        }
    }

    $diagItens = @()

    # --- Git Bash ---
    if ($CheckGit) {
        $gitStatus = "Nao instalado"; $gitColor = "Red"; $gitAcao = "instalar"
        try {
            $gitCands = @("C:\Program Files\Git","C:\Program Files (x86)\Git","$env:LOCALAPPDATA\Programs\Git")
            $gitExe = $null
            foreach ($c in $gitCands) {
                if (Test-Path "$c\cmd\git.exe") { $gitExe = "$c\cmd\git.exe"; break }
            }
            if (-not $gitExe) {
                $reg = Get-ItemProperty "HKLM:\SOFTWARE\GitForWindows" -ErrorAction SilentlyContinue
                if ($reg) { $gitExe = "$($reg.InstallPath)\cmd\git.exe" }
            }
            if (-not $gitExe) {
                $gitCmd = Get-Command git -ErrorAction SilentlyContinue
                if ($gitCmd) { $gitExe = $gitCmd.Source }
            }
            if ($gitExe -and (Test-Path $gitExe)) {
                $gv = (& $gitExe --version 2>&1) -replace "git version " -replace "\.windows\.\d+$"
                $gitLatest = $null
                try {
                    $rel = Invoke-RestMethod "https://api.github.com/repos/git-for-windows/git/releases/latest" -ErrorAction SilentlyContinue
                    $gitLatest = ($rel.tag_name -replace "^v" -replace "\.windows\.\d+$")
                } catch {}
                if ($gitLatest -and $gv.Trim() -ne $gitLatest) {
                    $gitStatus = "v$($gv.Trim()) -> $gitLatest"; $gitColor = "Yellow"; $gitAcao = "atualizar"
                } else {
                    $gitStatus = "v$($gv.Trim()) - Atualizado"; $gitColor = "Green"; $gitAcao = "ok"
                }
            }
        } catch {}
        $diagItens += [PSCustomObject]@{ Nome = "Git Bash      "; Status = $gitStatus; Cor = $gitColor; Acao = $gitAcao }
    }

    # --- Claude Code CLI ---
    if ($CheckClaudeCLI) {
        $claudeStatus = "Nao instalado"; $claudeColor = "Red"; $claudeAcao = "instalar"
        try {
            $cv = & claude --version 2>&1 | Out-String
            if ($cv -match "\d+\.\d+\.\d+") {
                $instV = ($cv -replace "[^\d\.]").Trim() -split "\s+" | Select-Object -First 1
                $npmInfo = Invoke-RestMethod "https://registry.npmjs.org/@anthropic-ai/claude-code/latest" -ErrorAction SilentlyContinue
                if ($npmInfo -and $instV -ne $npmInfo.version) {
                    $claudeStatus = "v$instV -> $($npmInfo.version)"; $claudeColor = "Yellow"; $claudeAcao = "atualizar"
                } else {
                    $claudeStatus = "v$instV - Atualizado"; $claudeColor = "Green"; $claudeAcao = "ok"
                }
            }
        } catch {}
        $diagItens += [PSCustomObject]@{ Nome = "Claude Code   "; Status = $claudeStatus; Cor = $claudeColor; Acao = $claudeAcao }
    }

    # --- Codex CLI ---
    if ($CheckCodexCLI) {
        $codexCliStatus = "Nao instalado"; $codexCliColor = "Red"; $codexCliAcao = "instalar"
        try {
            $cxv = & codex --version 2>&1 | Out-String
            if ($cxv -match "\d+\.\d+\.\d+") {
                $instV = ($cxv -replace "[^\d\.]").Trim() -split "\s+" | Select-Object -First 1
                $npmInfo = Invoke-RestMethod "https://registry.npmjs.org/@openai/codex/latest" -ErrorAction SilentlyContinue
                if ($npmInfo -and $instV -ne $npmInfo.version) {
                    $codexCliStatus = "v$instV -> $($npmInfo.version)"; $codexCliColor = "Yellow"; $codexCliAcao = "atualizar"
                } else {
                    $codexCliStatus = "v$instV - Atualizado"; $codexCliColor = "Green"; $codexCliAcao = "ok"
                }
            }
        } catch {}
        $diagItens += [PSCustomObject]@{ Nome = "Codex CLI     "; Status = $codexCliStatus; Cor = $codexCliColor; Acao = $codexCliAcao }
    }

    # --- OpenCode CLI ---
    if ($CheckOpenCode) {
        $openCodeStatus = "Nao instalado"; $openCodeColor = "Red"; $openCodeAcao = "instalar"
        try {
            $ocv = & opencode --version 2>&1 | Out-String
            if ($ocv -match "\d+\.\d+\.\d+") {
                $instV = ($ocv -replace "[^\d\.]").Trim() -split "\s+" | Select-Object -First 1
                $npmInfo = Invoke-RestMethod "https://registry.npmjs.org/opencode-ai/latest" -ErrorAction SilentlyContinue
                if ($npmInfo -and $instV -ne $npmInfo.version) {
                    $openCodeStatus = "v$instV -> $($npmInfo.version)"; $openCodeColor = "Yellow"; $openCodeAcao = "atualizar"
                } else {
                    $openCodeStatus = "v$instV - Atualizado"; $openCodeColor = "Green"; $openCodeAcao = "ok"
                }
            }
        } catch {}
        $diagItens += [PSCustomObject]@{ Nome = "OpenCode CLI  "; Status = $openCodeStatus; Cor = $openCodeColor; Acao = $openCodeAcao }
    }

    # --- Claude Desktop ---
    if ($CheckClaudeDesk) {
        $claudeDeskStatus = "Nao instalado"; $claudeDeskColor = "Red"; $claudeDeskAcao = "instalar"
        try {
            $pkg = Get-AppxPackage -Name "*Claude*" -ErrorAction SilentlyContinue
            if ($pkg) { $claudeDeskStatus = "v$($pkg.Version) - Instalado"; $claudeDeskColor = "Green"; $claudeDeskAcao = "ok" }
        } catch {}
        $diagItens += [PSCustomObject]@{ Nome = "Claude Desktop"; Status = $claudeDeskStatus; Cor = $claudeDeskColor; Acao = $claudeDeskAcao }
    }

    # --- Codex Desktop ---
    if ($CheckCodexDesk) {
        $codexDeskStatus = "Nao instalado"; $codexDeskColor = "Red"; $codexDeskAcao = "instalar"
        try {
            $listById = & winget list --id 9PLM9XGG6VKS --accept-source-agreements 2>&1 | Out-String
            if ($listById -notmatch "Nenhum pacote" -and $listById -notmatch "No installed" -and $listById.Trim().Length -gt 50) {
                $codexDeskStatus = "Instalado"; $codexDeskColor = "Green"; $codexDeskAcao = "ok"
            } else {
                $listAll = & winget list --accept-source-agreements 2>&1 | Out-String
                if ($listAll -match "9PLM9XGG6VKS" -or $listAll -match "OpenAI Codex") {
                    $codexDeskStatus = "Instalado"; $codexDeskColor = "Green"; $codexDeskAcao = "ok"
                }
            }
            if ($codexDeskAcao -eq "instalar") {
                $appx = Get-AppxPackage -Name "*Codex*" -ErrorAction SilentlyContinue
                if ($appx) { $codexDeskStatus = "Instalado"; $codexDeskColor = "Green"; $codexDeskAcao = "ok" }
            }
        } catch {}
        $diagItens += [PSCustomObject]@{ Nome = "Codex Desktop "; Status = $codexDeskStatus; Cor = $codexDeskColor; Acao = $codexDeskAcao }
    }

    # --- OpenCode Desktop ---
    if ($CheckOpenDesk) {
        $openDeskStatus = "Nao instalado"; $openDeskColor = "Red"; $openDeskAcao = "instalar"
        try {
            $listAll = & winget list --accept-source-agreements 2>&1 | Out-String
            if ($listAll -match "SST.OpenCodeDesktop" -or $listAll -match "OpenCode") {
                $openDeskStatus = "Instalado"; $openDeskColor = "Green"; $openDeskAcao = "ok"
            }
        } catch {}
        $diagItens += [PSCustomObject]@{ Nome = "OpenCode Desk "; Status = $openDeskStatus; Cor = $openDeskColor; Acao = $openDeskAcao }
    }

    # --- Exibe resultado ---
    Write-Host "  Ferramenta         Status" -ForegroundColor White
    Write-Host "  -----------------------------------------------" -ForegroundColor DarkGray
    foreach ($item in $diagItens) {
        $icone = switch ($item.Acao) {
            "ok"        { "[ OK]" }
            "atualizar" { "[AVS]" }
            default     { "[ERR]" }
        }
        Write-Host "  $icone $($item.Nome) : $($item.Status)" -ForegroundColor $item.Cor
    }
    Write-Host ""

    $acoesPendentes = $diagItens | Where-Object { $_.Acao -ne "ok" }

    if ($acoesPendentes.Count -eq 0) {
        Write-Host "  Tudo instalado e atualizado! Nenhuma acao necessaria." -ForegroundColor Green
        Write-Host ""
        Write-Host "============================================================`n" -ForegroundColor Cyan
        return $false  # Nao precisa prosseguir
    }

    Write-Host "  Acoes necessarias:" -ForegroundColor White
    foreach ($a in $acoesPendentes) {
        $label = if ($a.Acao -eq "instalar") { "Instalar" } else { "Atualizar" }
        Write-Host "    - $label $($a.Nome.Trim())" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "============================================================`n" -ForegroundColor Cyan

    if (-not (Confirm-Tecla "Deseja prosseguir?")) {
        return $false  # Usuario cancelou
    }
    Write-Host ""
    return $true  # Prosseguir com instalacao
}

# ----------------------------------------------------------
# LOOP PRINCIPAL - menu principal: Instalar ou Remover
# ----------------------------------------------------------
do {
Clear-Host
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "   Gerenciador de Ferramentas Dev" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  O que deseja fazer?" -ForegroundColor White
Write-Host ""
Write-Host "  [1] Instalar / Atualizar ferramentas" -ForegroundColor Yellow
Write-Host "  [2] Remover ferramentas" -ForegroundColor Yellow
Write-Host "  [9] Versao e historico de atualizacoes" -ForegroundColor DarkGray
Write-Host "  [0] Sair" -ForegroundColor Yellow
Write-Host ""

$modoPrincipal = $null
while ($modoPrincipal -notin @('0','1','2','9')) {
    Write-Host "  Digite o numero da opcao: " -ForegroundColor White -NoNewline
    $key = [Console]::ReadKey($true)
    $modoPrincipal = $key.KeyChar.ToString()
    Write-Host $modoPrincipal
    if ($modoPrincipal -notin @('0','1','2','9')) {
        Write-Host "  Opcao invalida. Tente novamente." -ForegroundColor Red
    }
}

if ($modoPrincipal -eq '0') {
    Write-Host "`nSaindo..." -ForegroundColor Gray
    break
}

# ── MODO VERSAO ───────────────────────────────────────────────
if ($modoPrincipal -eq '9') {
    Clear-Host
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "   Versao e Historico de Atualizacoes" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Script  : Gerenciador de Ferramentas Dev" -ForegroundColor White
    Write-Host "  Versao  : $SCRIPT_VERSION" -ForegroundColor Green
    Write-Host "  Data    : $SCRIPT_DATA" -ForegroundColor White
    Write-Host ""
    Write-Host "  --------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  Historico de alteracoes:" -ForegroundColor White
    Write-Host "  --------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""

    $versaoAtual = ""
    foreach ($entry in $CHANGELOG) {
        if ($entry.Versao -ne $versaoAtual) {
            $versaoAtual = $entry.Versao
            Write-Host "  v$($entry.Versao)  ($($entry.Data))" -ForegroundColor Yellow
        }
        Write-Host "    - $($entry.Descricao)" -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host "============================================================`n" -ForegroundColor Cyan
    Write-Host ""
    if (-not (Confirm-Tecla "Voltar ao menu?")) {
        Write-Host "`nSaindo..." -ForegroundColor Gray
        break
    }
    continue
}

# ── MODO REMOCAO ──────────────────────────────────────────────
if ($modoPrincipal -eq '2') {
    Clear-Host
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "   Remover Ferramentas Dev" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Selecione o que deseja remover:" -ForegroundColor White
    Write-Host ""
    Write-Host "  --- Ferramentas CLI ---" -ForegroundColor DarkGray
    Write-Host "  [1] Tudo" -ForegroundColor Red
    Write-Host "  [2] Claude Code (CLI)" -ForegroundColor Red
    Write-Host "  [3] Codex CLI (OpenAI)" -ForegroundColor Red
    Write-Host "  [4] OpenCode" -ForegroundColor Red
    Write-Host "  [5] Somente CLI  [Claude Code + Codex CLI + OpenCode]" -ForegroundColor Red
    Write-Host ""
    Write-Host "  --- Apps Desktop ---" -ForegroundColor DarkGray
    Write-Host "  [6] Claude Desktop" -ForegroundColor Red
    Write-Host "  [7] Codex Desktop (OpenAI)" -ForegroundColor Red
    Write-Host "  [8] OpenCode Desktop" -ForegroundColor Red
    Write-Host "  [9] Somente Desktop  [Claude Desktop + Codex Desktop + OpenCode Desktop]" -ForegroundColor Red
    Write-Host ""
    Write-Host "  [0] Voltar" -ForegroundColor Yellow
    Write-Host ""

    $opcaoRem = $null
    while ($opcaoRem -notin @('0','1','2','3','4','5','6','7','8','9')) {
        Write-Host "  Digite o numero da opcao: " -ForegroundColor White -NoNewline
        $key = [Console]::ReadKey($true)
        $opcaoRem = $key.KeyChar.ToString()
        Write-Host $opcaoRem
        if ($opcaoRem -notin @('0','1','2','3','4','5','6','7','8','9')) {
            Write-Host "  Opcao invalida. Tente novamente." -ForegroundColor Red
        }
    }

    if ($opcaoRem -eq '0') { continue }

    $remClaudeCLI  = $opcaoRem -in @('1','2','5')
    $remCodexCLI   = $opcaoRem -in @('1','3','5')
    $remOpenCode   = $opcaoRem -in @('1','4','5')
    $remClaudeDesk = $opcaoRem -in @('1','6','9')
    $remCodexDesk  = $opcaoRem -in @('1','7','9')
    $remOpenDesk   = $opcaoRem -in @('1','8','9')

    Write-Host ""
    Write-Host "  Itens que serao removidos:" -ForegroundColor White
    if ($remClaudeCLI)  { Write-Host "    - Claude Code (CLI)"          -ForegroundColor Red }
    if ($remCodexCLI)   { Write-Host "    - Codex CLI"                  -ForegroundColor Red }
    if ($remOpenCode)   { Write-Host "    - OpenCode"                   -ForegroundColor Red }
    if ($remClaudeDesk) { Write-Host "    - Claude Desktop"             -ForegroundColor Red }
    if ($remCodexDesk)  { Write-Host "    - Codex Desktop"              -ForegroundColor Red }
    if ($remOpenDesk)   { Write-Host "    - OpenCode Desktop"           -ForegroundColor Red }
    Write-Host ""

    if (-not (Confirm-Tecla "Confirmar remocao?")) { continue }

    try {
        $wingetOk = $false
        try { $null = & winget --version 2>&1; $wingetOk = $true } catch { }

        # Garante npm no PATH para remocao CLI
        $npmPaths = @("$env:ProgramFiles
odejs", "$env:APPDATA
pm")
        foreach ($p in $npmPaths) {
            if ((Test-Path -LiteralPath $p -ErrorAction SilentlyContinue) -and ($env:Path -notlike "*$p*")) {
                $env:Path = "$p;$env:Path"
            }
        }

        if ($remClaudeCLI) {
            Write-Step "Removendo Claude Code (CLI)..."

            # Metodo 1: winget
            if ($wingetOk) {
                try {
                    $out = & winget uninstall --id Anthropic.ClaudeCode --silent --accept-source-agreements 2>&1 | Out-String
                    Write-Host $out
                } catch { }
            }

            # Metodo 2: npm uninstall
            try { & npm uninstall -g @anthropic-ai/claude-code 2>&1 | ForEach-Object { Write-Host $_ } } catch { }

            # Metodo 3: busca ampla por executavel claude em todos os locais conhecidos
            $claudeLocais = @(
                "$env:USERPROFILE\.local\bin\claude.exe",
                "$env:USERPROFILE\.local\bin\claude",
                "$env:USERPROFILE\.local\share\claude",
                "$env:APPDATA\npm\claude.exe",
                "$env:APPDATA\npm\claude",
                "$env:APPDATA\npm\claude.cmd",
                "$env:APPDATA\npm\claude.ps1",
                "$env:APPDATA\npm\node_modules\@anthropic-ai\claude-code",
                "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Anthropic.ClaudeCode_Microsoft.Winget.Source_8wekyb3d8bbwe",
                "$env:LOCALAPPDATA\Microsoft\WinGet\Links\claude.exe",
                "$env:ProgramFiles\Anthropic\Claude Code",
                "$env:USERPROFILE\.claude\local"
            )
            foreach ($p in $claudeLocais) {
                if (Test-Path -LiteralPath $p -ErrorAction SilentlyContinue) {
                    Write-Ok "Encontrado em: $p"
                    Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue
                }
            }

            # Busca dinamica: procura claude.exe em qualquer lugar no perfil do usuario
            try {
                $encontrados = Get-ChildItem -Path $env:USERPROFILE -Filter "claude.exe" -Recurse -ErrorAction SilentlyContinue |
                    Where-Object { $_.FullName -notmatch "AnthropicClaude" } # Exclui Claude Desktop
                foreach ($f in $encontrados) {
                    Write-Ok "Encontrado em: $($f.FullName)"
                    Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
                }
            } catch { }

            # Remove variaveis de ambiente relacionadas ao Claude Code
            Write-Step "Removendo variaveis de ambiente do Claude Code..."
            $claudeEnvVars = @(
                "CLAUDE_CODE_GIT_BASH_PATH",
                "CLAUDE_CODE_USE_BEDROCK",
                "CLAUDE_CODE_USE_VERTEX",
                "CLAUDE_CODE_API_KEY_HELPER_TTL_MS",
                "CLAUDE_CODE_SKIP_PERMISSIONS_CHECK"
            )
            foreach ($var in $claudeEnvVars) {
                $val = [Environment]::GetEnvironmentVariable($var, "User")
                if ($val) {
                    [Environment]::SetEnvironmentVariable($var, $null, "User")
                    Write-Ok "Variavel removida: $var"
                }
                $valM = [Environment]::GetEnvironmentVariable($var, "Machine")
                if ($valM) {
                    [Environment]::SetEnvironmentVariable($var, $null, "Machine")
                    Write-Ok "Variavel de sistema removida: $var"
                }
            }

            # Remove entradas do PATH que apontam para o Claude
            Write-Step "Limpando PATH..."
            $pathUser = [Environment]::GetEnvironmentVariable("Path", "User")
            $pathEntradas = $pathUser -split ";"
            $pathLimpo = ($pathEntradas | Where-Object {
                $_ -notmatch "claude" -and
                $_ -ne "$env:USERPROFILE\.local\bin" -or
                (Test-Path -LiteralPath $_ -ErrorAction SilentlyContinue)
            }) -join ";"
            if ($pathLimpo -ne $pathUser) {
                [Environment]::SetEnvironmentVariable("Path", $pathLimpo, "User")
                Write-Ok "PATH atualizado."
            }

            # Verifica resultado
            $claudeAinda = $false
            try { $null = & claude --version 2>&1; $claudeAinda = $true } catch { }
            if (-not $claudeAinda) {
                Write-Ok "Claude Code removido com sucesso."
            } else {
                Write-Warn "Claude Code ainda detectado. Pode ser necessario reiniciar o terminal."
            }
        }

        if ($remCodexCLI) {
            Write-Step "Removendo Codex CLI..."

            try { & npm uninstall -g @openai/codex 2>&1 | ForEach-Object { Write-Host $_ } } catch { }

            $codexLocais = @(
                "$env:APPDATA\npm\codex.exe",
                "$env:APPDATA\npm\codex",
                "$env:APPDATA\npm\codex.cmd",
                "$env:APPDATA\npm\codex.ps1",
                "$env:APPDATA\npm\node_modules\@openai\codex",
                "$env:LOCALAPPDATA\Microsoft\WinGet\Links\codex.exe"
            )
            foreach ($p in $codexLocais) {
                if (Test-Path -LiteralPath $p -ErrorAction SilentlyContinue) {
                    Write-Ok "Encontrado em: $p"
                    Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue
                }
            }

            # Remove variaveis de ambiente do Codex
            foreach ($var in @("OPENAI_API_KEY_PATH","CODEX_HOME")) {
                if ([Environment]::GetEnvironmentVariable($var, "User")) {
                    [Environment]::SetEnvironmentVariable($var, $null, "User")
                    Write-Ok "Variavel removida: $var"
                }
            }

            $codexAinda = $false
            try { $null = & codex --version 2>&1; $codexAinda = $true } catch { }
            if (-not $codexAinda) {
                Write-Ok "Codex CLI removido com sucesso."
            } else {
                Write-Warn "Codex CLI ainda detectado. Pode ser necessario reiniciar o terminal."
            }
        }

        if ($remOpenCode) {
            Write-Step "Removendo OpenCode..."

            try { & npm uninstall -g opencode-ai 2>&1 | ForEach-Object { Write-Host $_ } } catch { }

            $openLocais = @(
                "$env:APPDATA\npm\opencode.exe",
                "$env:APPDATA\npm\opencode",
                "$env:APPDATA\npm\opencode.cmd",
                "$env:APPDATA\npm\opencode.ps1",
                "$env:APPDATA\npm\node_modules\opencode-ai",
                "$env:LOCALAPPDATA\Microsoft\WinGet\Links\opencode.exe"
            )
            foreach ($p in $openLocais) {
                if (Test-Path -LiteralPath $p -ErrorAction SilentlyContinue) {
                    Write-Ok "Encontrado em: $p"
                    Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue
                }
            }

            $openAinda = $false
            try { $null = & opencode --version 2>&1; $openAinda = $true } catch { }
            if (-not $openAinda) {
                Write-Ok "OpenCode removido com sucesso."
            } else {
                Write-Warn "OpenCode ainda detectado. Pode ser necessario reiniciar o terminal."
            }
        }

        if ($remClaudeDesk) {
            Write-Step "Removendo Claude Desktop..."
            $removido = $false

            # Metodo 1: desinstalador nativo (Update.exe)
            $updateExe = "$env:LOCALAPPDATA\AnthropicClaude\Update.exe"
            if (Test-Path -LiteralPath $updateExe -ErrorAction SilentlyContinue) {
                try {
                    Start-Process $updateExe -ArgumentList "--uninstall" -Wait -NoNewWindow
                    $removido = $true
                } catch { }
            }

            # Metodo 2: winget
            if (-not $removido -and $wingetOk) {
                try {
                    $out = & winget uninstall --id Anthropic.Claude --silent --accept-source-agreements 2>&1 | Out-String
                    Write-Host $out
                    if ($out -notmatch "nao encontrado|not found|No installed") { $removido = $true }
                } catch { }
            }

            # Metodo 3: remover pasta diretamente
            $claudeDeskPath = "$env:LOCALAPPDATA\AnthropicClaude"
            if (Test-Path -LiteralPath $claudeDeskPath -ErrorAction SilentlyContinue) {
                try { Remove-Item -LiteralPath $claudeDeskPath -Recurse -Force -ErrorAction SilentlyContinue; $removido = $true } catch { }
            }

            if ($removido) {
                Write-Ok "Claude Desktop removido com sucesso."
            } else {
                Write-Warn "Nao foi possivel remover automaticamente. Remova pelo Painel de Controle > Aplicativos."
            }
        }

        if ($remCodexDesk) {
            Write-Step "Removendo Codex Desktop..."
            $removido = $false
            if ($wingetOk) {
                # Tenta pelo ID da Store e pelo nome
                foreach ($id in @('9PLM9XGG6VKS', 'OpenAI.Codex')) {
                    try {
                        $out = & winget uninstall --id $id --silent --accept-source-agreements 2>&1 | Out-String
                        if ($out -notmatch "nao encontrado|not found|No installed") {
                            $removido = $true; break
                        }
                    } catch { }
                }
            }
            if (-not $removido) {
                try {
                    $pkg = Get-AppxPackage -Name "*Codex*" -ErrorAction SilentlyContinue
                    if ($pkg) {
                        Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction SilentlyContinue
                        $removido = $true
                    }
                } catch { }
            }
            if ($removido) {
                Write-Ok "Codex Desktop removido com sucesso."
            } else {
                Write-Warn "Nao foi possivel remover automaticamente. Remova pelo Painel de Controle."
            }
        }

        if ($remOpenDesk) {
            Write-Step "Removendo OpenCode Desktop..."
            $removido = $false
            if ($wingetOk) {
                try {
                    $out = & winget uninstall --id SST.OpenCodeDesktop --silent --accept-source-agreements 2>&1 | Out-String
                    if ($out -notmatch "nao encontrado|not found|No installed") { $removido = $true }
                } catch { }
            }
            if (-not $removido) {
                try {
                    $pkg = Get-AppxPackage -Name "*OpenCode*" -ErrorAction SilentlyContinue
                    if ($pkg) {
                        Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction SilentlyContinue
                        $removido = $true
                    }
                } catch { }
            }
            if ($removido) {
                Write-Ok "OpenCode Desktop removido com sucesso."
            } else {
                Write-Warn "Nao foi possivel remover automaticamente. Remova pelo Painel de Controle."
            }
        }

        Write-Host "`n============================================================" -ForegroundColor Cyan
        Write-Host "  Remocao concluida!" -ForegroundColor Green
        Write-Host "============================================================`n" -ForegroundColor Cyan

    } catch {
        Write-Host "`n[ERR] Erro durante remocao: $_" -ForegroundColor Red
    }

    Write-Host ""
    if (-not (Confirm-Tecla "Voltar ao menu?")) {
        Write-Host "`nSaindo..." -ForegroundColor Gray
        break
    }
    continue
}

# ── MODO INSTALACAO ───────────────────────────────────────────
Clear-Host
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "   Instalar / Atualizar Ferramentas Dev" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Selecione o que deseja instalar/atualizar:" -ForegroundColor White
Write-Host ""
Write-Host "  [1] Tudo  [CLI + Desktop]" -ForegroundColor Green
Write-Host ""
Write-Host "  --- Ferramentas CLI ---" -ForegroundColor DarkGray
Write-Host "  [2] Claude Code (CLI)           [instala Git Bash automaticamente]" -ForegroundColor Yellow
Write-Host "  [3] Codex CLI (OpenAI)" -ForegroundColor Yellow
Write-Host "  [4] OpenCode (CLI)" -ForegroundColor Yellow
Write-Host "  [5] Somente CLI  [Claude Code + Codex CLI + OpenCode]" -ForegroundColor Yellow
Write-Host ""
Write-Host "  --- Apps Desktop ---" -ForegroundColor DarkGray
Write-Host "  [6] Claude Desktop" -ForegroundColor Yellow
Write-Host "  [7] Codex Desktop (OpenAI)" -ForegroundColor Yellow
Write-Host "  [8] OpenCode Desktop" -ForegroundColor Yellow
Write-Host "  [9] Somente Desktop  [Claude Desktop + Codex Desktop + OpenCode Desktop]" -ForegroundColor Yellow
Write-Host ""
Write-Host "  [0] Voltar" -ForegroundColor Yellow
Write-Host ""

$opcao = $null
while ($opcao -notin @('0','1','2','3','4','5','6','7','8','9')) {
    Write-Host "  Digite o numero da opcao: " -ForegroundColor White -NoNewline
    $key = [Console]::ReadKey($true)
    $opcao = $key.KeyChar.ToString()
    Write-Host $opcao
    if ($opcao -notin @('0','1','2','3','4','5','6','7','8','9')) {
        Write-Host "  Opcao invalida. Tente novamente." -ForegroundColor Red
    }
}

if ($opcao -eq '0') { continue }

$instalarGit        = $opcao -in @('1','2','5')
$instalarClaudeCLI  = $opcao -in @('1','2','5')
$instalarCodexCLI   = $opcao -in @('1','3','5')
$instalarOpenCode   = $opcao -in @('1','4','5')
$instalarClaudeDesk = $opcao -in @('1','6','9')
$instalarCodexDesk  = $opcao -in @('1','7','9')
$instalarOpenDesk   = $opcao -in @('1','8','9')
$codexDesktopOk     = $false

Write-Host ""
Write-Host "  Itens selecionados:" -ForegroundColor White
if ($instalarGit)        { Write-Host "    - Git Bash"                  -ForegroundColor Cyan }
if ($instalarClaudeCLI)  { Write-Host "    - Claude Code (CLI)"         -ForegroundColor Cyan }
if ($instalarCodexCLI)   { Write-Host "    - Codex CLI"                 -ForegroundColor Cyan }
if ($instalarOpenCode)   { Write-Host "    - OpenCode"                  -ForegroundColor Cyan }
if ($instalarClaudeDesk) { Write-Host "    - Claude Desktop"            -ForegroundColor Cyan }
if ($instalarCodexDesk)  { Write-Host "    - Codex Desktop"             -ForegroundColor Cyan }
if ($instalarOpenDesk)   { Write-Host "    - OpenCode Desktop"          -ForegroundColor Cyan }
Write-Host ""
Pause-Readable 2

try {

# ----------------------------------------------------------
# Atualiza PATH na sessao para detectar ferramentas ja instaladas
# ----------------------------------------------------------
$env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
            "$env:USERPROFILE\.local\bin" + ";" +
            [Environment]::GetEnvironmentVariable("Path", "User")

# ----------------------------------------------------------
# Garante que npm instala no perfil do usuario logado
# (evita instalacao no perfil do Administrador quando elevado)
# ----------------------------------------------------------
$npmGlobalDir = $null
try {
    # Detecta o usuario real (nao o admin elevado)
    $usuarioReal = [Environment]::GetEnvironmentVariable("USERNAME", "User")
    if (-not $usuarioReal) { $usuarioReal = $env:USERNAME }

    # Define o prefix do npm para o usuario correto
    $npmPrefix = "$env:APPDATA\npm"
    $null = & npm config set prefix $npmPrefix 2>&1
    $npmGlobalDir = $npmPrefix

    # Garante que esta no PATH da sessao
    if ($env:Path -notlike "*$npmPrefix*") {
        $env:Path = "$npmPrefix;$env:Path"
    }
} catch { }

# ----------------------------------------------------------
# Detecta tipo de sistema operacional
# ProductType: 1 = Workstation, 2 = Domain Controller, 3 = Server
# ----------------------------------------------------------
$wingetOk = $false
try { $null = & winget --version 2>&1; $wingetOk = $true } catch { }

if ($wingetOk) {
    Write-Ok "winget disponivel. Usando instalacao silenciosa."
} else {
    Write-Warn "winget nao disponivel. Usando metodos alternativos."
}

# ----------------------------------------------------------
# DIAGNOSTICO - chama funcao para as ferramentas selecionadas
# ----------------------------------------------------------
$prosseguir = Invoke-Diagnostico `
    -CheckGit        $instalarGit `
    -CheckClaudeCLI  $instalarClaudeCLI `
    -CheckCodexCLI   $instalarCodexCLI `
    -CheckOpenCode   $instalarOpenCode `
    -CheckClaudeDesk $instalarClaudeDesk `
    -CheckCodexDesk  $instalarCodexDesk `
    -CheckOpenDesk   $instalarOpenDesk

if (-not $prosseguir) {
    Write-Host ""
    if (-not (Confirm-Tecla "Voltar ao menu?")) { break }
    continue
}

# ============================================================
# 1. GIT BASH
# ============================================================
if ($instalarGit) {

    Write-Step "Verificando Git Bash..."

    $gitCandidatePaths = @(
        "C:\Program Files\Git",
        "C:\Program Files (x86)\Git",
        "$env:LOCALAPPDATA\Programs\Git",
        "$env:ProgramFiles\Git",
        "${env:ProgramFiles(x86)}\Git"
    )

    $gitBashPath = $null
    $gitCmdExe   = $null

    foreach ($candidate in $gitCandidatePaths) {
        $candidateCmd = "$candidate\cmd\git.exe"
        if (Test-Path $candidateCmd) {
            $gitBashPath = $candidate
            $gitCmdExe   = $candidateCmd
            break
        }
    }

    if (-not $gitBashPath) {
        try {
            $gitInPath   = (Get-Command git -ErrorAction Stop).Source
            $gitBashPath = Split-Path (Split-Path $gitInPath -Parent) -Parent
            $gitCmdExe   = $gitInPath
            Write-Ok "Git encontrado via PATH: $gitInPath"
        } catch { }
    }

    # Busca no registro do Windows como ultimo recurso
    if (-not $gitBashPath) {
        try {
            $regPaths = @(
                "HKLM:\SOFTWARE\GitForWindows",
                "HKCU:\SOFTWARE\GitForWindows"
            )
            foreach ($reg in $regPaths) {
                $regVal = Get-ItemProperty -Path $reg -Name InstallPath -ErrorAction SilentlyContinue
                if ($regVal -and (Test-Path "$($regVal.InstallPath)\cmd\git.exe")) {
                    $gitBashPath = $regVal.InstallPath
                    $gitCmdExe   = "$gitBashPath\cmd\git.exe"
                    Write-Ok "Git encontrado via registro: $gitBashPath"
                    break
                }
            }
        } catch { }
    }

    try {
        $release   = Invoke-RestMethod "https://api.github.com/repos/git-for-windows/git/releases/latest"
        $asset     = $release.assets | Where-Object { $_.name -match "Git-.*-64-bit\.exe" } | Select-Object -First 1
        $latestVer = ($release.tag_name -replace '^v' -replace '\.windows\.\d+$')
    } catch {
        Write-Warn "Nao foi possivel consultar a versao mais recente do Git Bash: $_"
        $latestVer = $null
        $asset     = $null
    }

    if ($gitBashPath) {
        Write-Ok "Git Bash encontrado em: $gitBashPath"

        if ($latestVer -and (Test-Path $gitCmdExe)) {
            try {
                $installedOutput = & $gitCmdExe --version 2>&1
                $installedVer    = ($installedOutput -replace '^git version ' -replace '\.windows\.\d+$').Trim()

                Write-Ok "Versao instalada   : $installedVer"
                Write-Ok "Versao mais recente: $latestVer"

                if ($installedVer -eq $latestVer) {
                    Write-Ok "Git Bash esta atualizado. Nenhuma acao necessaria."
                    Pause-Readable 3
                } else {
                    Write-Warn "Atualizacao disponivel: $installedVer -> $latestVer"
                    Write-Step "Baixando e instalando atualizacao do Git Bash..."
                    $gitInstaller = "$env:TEMP\git-installer.exe"
                    try {
                        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $gitInstaller -UseBasicParsing
                        $installArgs = @(
                            "/VERYSILENT", "/NORESTART", "/NOCANCEL", "/SP-",
                            "/CLOSEAPPLICATIONS", "/RESTARTAPPLICATIONS",
                            "/COMPONENTS=icons,ext\reg\shellhere,assoc,assoc_sh",
                            "/DIR=`"$gitBashPath`""
                        )
                        Start-Process -FilePath $gitInstaller -ArgumentList $installArgs -Wait -NoNewWindow
                        Write-Ok "Git Bash atualizado para $latestVer com sucesso."
                        Pause-Readable 3
                    } catch {
                        Write-Fail "Erro ao atualizar Git Bash: $_"
                        Pause-Readable 3
                    } finally {
                        if (Test-Path $gitInstaller) { Remove-Item $gitInstaller -Force }
                    }
                }
            } catch {
                Write-Warn "Nao foi possivel verificar a versao instalada do Git: $_"
                Pause-Readable 3
            }
        } else {
            Write-Warn "Nao foi possivel comparar versoes. Verifique manualmente se o Git Bash esta atualizado."
            Pause-Readable 3
        }

    } else {
        $gitBashPath = "$env:LOCALAPPDATA\Programs\Git"
        $gitCmdExe   = "$gitBashPath\cmd\git.exe"

        if (-not $asset) {
            Write-Fail "Nao foi possivel obter o instalador do Git Bash. Verifique sua conexao."
            Pause-Readable 3
        } else {
            Write-Step "Git Bash nao encontrado. Iniciando instalacao..."
            Write-Ok "Versao encontrada: $($asset.name)"
            $gitInstaller = "$env:TEMP\git-installer.exe"
            try {
                Write-Step "Baixando Git Bash..."
                Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $gitInstaller -UseBasicParsing
                Write-Step "Instalando Git Bash (modo silencioso)..."
                $installArgs = @(
                    "/VERYSILENT", "/NORESTART", "/NOCANCEL", "/SP-",
                    "/CLOSEAPPLICATIONS", "/RESTARTAPPLICATIONS",
                    "/COMPONENTS=icons,ext\reg\shellhere,assoc,assoc_sh",
                    "/DIR=`"$gitBashPath`""
                )
                Start-Process -FilePath $gitInstaller -ArgumentList $installArgs -Wait -NoNewWindow
                if (Test-Path $gitCmdExe) {
                    Write-Ok "Git Bash instalado com sucesso em: $gitBashPath"
                    Pause-Readable 3
                } else {
                    Write-Fail "Instalacao do Git Bash falhou. Verifique manualmente."
                    Pause-Readable 3
                }
            } catch {
                Write-Fail "Erro ao instalar Git Bash: $_"
                Pause-Readable 3
            } finally {
                if (Test-Path $gitInstaller) { Remove-Item $gitInstaller -Force }
            }
        }
    }

    if ($gitBashPath -and $instalarClaudeCLI) {
        Write-Step "Configurando CLAUDE_CODE_GIT_BASH_PATH..."
        $currentVal = [Environment]::GetEnvironmentVariable("CLAUDE_CODE_GIT_BASH_PATH", "User")
        if ($currentVal -eq $gitBashPath) {
            Write-Ok "CLAUDE_CODE_GIT_BASH_PATH ja esta configurado. Nenhuma alteracao necessaria."
        } else {
            [Environment]::SetEnvironmentVariable("CLAUDE_CODE_GIT_BASH_PATH", $gitBashPath, "User")
            $env:CLAUDE_CODE_GIT_BASH_PATH = $gitBashPath
            Write-Ok "CLAUDE_CODE_GIT_BASH_PATH = $gitBashPath"
        }
        Pause-Readable 3
    }
}

# ============================================================
# 2. CLAUDE DESKTOP
#    Com winget    → instalacao silenciosa
#    Sem winget    → orienta download manual
# ============================================================
if ($instalarClaudeDesk) {

    Write-Step "Verificando Claude Desktop..."

    # Detecta se ja esta instalado
    $claudeDesktopInstalled = $false
    try {
        $pkg = Get-AppxPackage -Name "*Claude*" -ErrorAction SilentlyContinue
        if ($pkg) { $claudeDesktopInstalled = $true }
    } catch { }

    if ($claudeDesktopInstalled) {
        Write-Ok "Claude Desktop ja esta instalado."
        Write-Ok "O Claude Desktop se atualiza automaticamente ao ser aberto."
        Pause-Readable 3
    } elseif ($wingetOk) {
        Write-Step "Instalando Claude Desktop via winget (silencioso)..."
        try {
            & winget install --id Anthropic.Claude --silent --accept-package-agreements --accept-source-agreements 2>&1 |
                Where-Object { $_ -notmatch '^\s*[-\\|/]\s*$' } |
                ForEach-Object { if ($_.Trim()) { Write-Host $_ } }
            Write-Ok "Claude Desktop instalado com sucesso."
            Write-Ok "Pesquise por 'Claude' no Menu Iniciar para abrir o app."
        } catch {
            Write-Fail "Falha ao instalar via winget: $_"
            Write-Warn "Baixe manualmente em: https://claude.ai/download"
        }
        Pause-Readable 3
    } else {
        Write-Warn "winget nao disponivel neste sistema."
        Write-Host ""
        Write-Host "  Baixe e instale o Claude Desktop manualmente:" -ForegroundColor White
        Write-Host "  https://claude.ai/redirect/claudedotcom.v1.63e31d8a-1218-4e42-b8e6-afbc20c95b9f/api/desktop/win32/x64/setup/latest/redirect" -ForegroundColor Cyan
        Write-Host ""
        if (Confirm-Tecla 'Deseja realizar o download agora?') {

            $setupPath = "$env:USERPROFILE\Downloads\ClaudeSetup.exe"
            try {
                Write-Step "Baixando Claude Desktop..."
                $headers = @{ 'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36' }
                Invoke-WebRequest -Uri "https://downloads.claude.ai/releases/win32/ClaudeSetup.exe" `
                    -OutFile $setupPath -UseBasicParsing -Headers $headers -MaximumRedirection 10
                # Valida que e um executavel (MZ header)
                $bytes = [System.IO.File]::ReadAllBytes($setupPath)
                if ($bytes[0] -eq 77 -and $bytes[1] -eq 90) {
                    Write-Ok "Download concluido: $setupPath"
                    Write-Warn "Execute o arquivo para instalar o Claude Desktop."
                } else {
                    Remove-Item $setupPath -Force
                    Write-Fail "O arquivo baixado nao e valido. Acesse o link manualmente."
                }
            } catch {
                Write-Fail "Falha no download: $_"
            }
        }
        Pause-Readable 3
    }
}

# ============================================================
# 3. CLAUDE CODE (CLI) — irm https://claude.ai/install.ps1 | iex
# ============================================================
if ($instalarClaudeCLI) {

    Write-Step "Verificando Claude Code (CLI)..."

    $claudeInstalled = $false
    $claudeVersionAtual = $null
    try {
        $claudeOut = & claude --version 2>&1
        $claudeVersionAtual = ($claudeOut | Out-String).Trim()
        $claudeInstalled = $true
    } catch { }

    # Detecta se e servidor Windows (ProductType 2=DC, 3=Server) ou maquina local (1=Workstation)
    $eServidor = $false
    try {
        $productType = (Get-WmiObject -Class Win32_OperatingSystem).ProductType
        # ProductType 1 = Workstation, 2 = Domain Controller, 3 = Server
        if ($productType -eq 2 -or $productType -eq 3) {
            $eServidor = $true
        }
    } catch { $eServidor = $false }

    if ($eServidor) {
        Write-Warn "Ambiente de servidor detectado. O instalador oficial pode falhar (Bun requer AVX)."
        Write-Ok "Usando npm como metodo de instalacao alternativo."
    }

    if ($claudeInstalled) {
        Write-Ok "Claude Code ja esta instalado. Versao: $claudeVersionAtual"
        Write-Step "Verificando atualizacoes..."
        try {
            $npmInfo      = Invoke-RestMethod "https://registry.npmjs.org/@anthropic-ai/claude-code/latest"
            $latestVer    = $npmInfo.version
            $installedVer = ($claudeVersionAtual -replace '^[^\d]*').Trim() -split '\s+' | Select-Object -First 1
            Write-Ok "Versao instalada   : $installedVer"
            Write-Ok "Versao mais recente: $latestVer"
            if ($installedVer -eq $latestVer) {
                Write-Ok "Claude Code esta atualizado. Nenhuma acao necessaria."
            } else {
                Write-Warn "Atualizacao disponivel: $installedVer -> $latestVer"
                Write-Step "Atualizando Claude Code..."
                if ($eServidor) {
                    if (-not (Ensure-NodeJS -WingetOk $wingetOk)) {
                        Write-Fail "Node.js nao disponivel. Nao foi possivel atualizar."
                    } else {
                        & npm install -g @anthropic-ai/claude-code 2>&1 | ForEach-Object { Write-Host $_ }
                        Write-Ok "Claude Code atualizado com sucesso."
                    }
                } else {
                    Invoke-RestMethod https://claude.ai/install.ps1 | Invoke-Expression
                    Write-Ok "Claude Code atualizado com sucesso."
                }
            }
        } catch {
            Write-Warn "Nao foi possivel verificar atualizacoes: $_"
        }
    } else {
        Write-Step "Claude Code nao encontrado. Instalando..."

        $claudeOk = $false

        if ($eServidor) {
            # Servidor: instala direto via npm (evita crash do Bun sem AVX)
            if (-not (Ensure-NodeJS -WingetOk $wingetOk)) {
                Write-Fail "Node.js nao disponivel. Nao e possivel instalar o Claude Code."
                Pause-Readable 3
            } else {
                Write-Step "Instalando Claude Code via npm..."
                try {
                    & npm install -g @anthropic-ai/claude-code 2>&1 | ForEach-Object { Write-Host $_ }
                    try { $null = & claude --version 2>&1; $claudeOk = $true } catch { }
                    if ($claudeOk) {
                        Write-Ok "Claude Code instalado com sucesso via npm."
                    } else {
                        Write-Warn "Claude Code instalado. Feche e reabra o terminal para usar."
                    }
                } catch {
                    Write-Fail "Falha na instalacao do Claude Code: $_"
                }
            }
        } else {
            # Maquina local: usa instalador oficial normalmente
            try {
                Invoke-RestMethod https://claude.ai/install.ps1 | Invoke-Expression
                try { $null = & claude --version 2>&1; $claudeOk = $true } catch { }
                if ($claudeOk) {
                    Write-Ok "Claude Code instalado com sucesso."
                } else {
                    Write-Warn "Claude Code instalado. Feche e reabra o terminal para usar."
                }
            } catch {
                Write-Fail "Falha na instalacao do Claude Code: $_"
            }
        }
    }
    Pause-Readable 3
}

# ============================================================
# 4. CODEX DESKTOP (OpenAI)
#    Com winget    → instalacao silenciosa
#    Sem winget    → orienta download manual (Microsoft Store)
# ============================================================
if ($instalarCodexDesk) {

    Write-Step "Verificando Codex Desktop (OpenAI)..."

    if ($wingetOk) {
        Write-Step "Verificando se Codex Desktop esta instalado..."

        $codexDesktopInstalled = $false
        $codexDesktopOk = $false
        try {
            # Tenta pelo ID direto primeiro
            $listById = & winget list --id 9PLM9XGG6VKS --accept-source-agreements 2>&1 | Out-String
            if ($listById -notmatch "Nenhum pacote" -and $listById -notmatch "No installed" -and $listById.Trim().Length -gt 50) {
                $codexDesktopInstalled = $true
            }
        } catch { }

        # Fallback: busca pelo nome na lista geral
        if (-not $codexDesktopInstalled) {
            try {
                $listAll = & winget list --accept-source-agreements 2>&1 | Out-String
                if ($listAll -match "9PLM9XGG6VKS" -or $listAll -match "Codex" -or $listAll -match "OpenAI Codex") {
                    $codexDesktopInstalled = $true
                }
            } catch { }
        }

        # Fallback: verifica via AppxPackage (Microsoft Store)
        if (-not $codexDesktopInstalled) {
            try {
                $appx = Get-AppxPackage -Name "*Codex*" -ErrorAction SilentlyContinue
                if ($appx) { $codexDesktopInstalled = $true }
            } catch { }
        }

        if ($codexDesktopInstalled) {
            Write-Ok "Codex Desktop ja esta instalado."
            $codexDesktopOk = $true
            Write-Step "Verificando atualizacoes..."
            try {
                & winget upgrade --id 9PLM9XGG6VKS --silent --accept-package-agreements --accept-source-agreements 2>&1 |
                    Where-Object { $_ -notmatch '^\s*[-\\|/]\s*$' } |
                    ForEach-Object { if ($_.Trim()) { Write-Host $_ } }
                Write-Ok "Codex Desktop atualizado."
            } catch {
                Write-Warn "Nao foi possivel verificar atualizacoes: $_"
            }
            Pause-Readable 3
        } else {
            Write-Step "Codex Desktop nao encontrado. Instalando via winget (silencioso)..."
            try {
                & winget install --id 9PLM9XGG6VKS --silent --accept-package-agreements --accept-source-agreements 2>&1 |
                    Where-Object { $_ -notmatch '^\s*[-\\|/]\s*$' } |
                    ForEach-Object { if ($_.Trim()) { Write-Host $_ } }
                $codexDesktopOk = $true
                Write-Ok "Codex Desktop instalado com sucesso."
                Write-Ok "Pesquise por 'Codex' no Menu Iniciar para abrir o app."
                Pause-Readable 3
            } catch {
                Write-Fail "Falha ao instalar Codex Desktop: $_"
                Write-Warn "Tente manualmente: https://apps.microsoft.com/detail/9plm9xgg6vks"
                Pause-Readable 4
            }
        }
    } else {
        $codexDesktopOk = $false
        Write-Warn "winget nao disponivel neste sistema."
        Write-Host ""
        Write-Host "  Baixe e instale o Codex Desktop manualmente:" -ForegroundColor White
        Write-Host "  https://get.microsoft.com/installer/download/9PLM9XGG6VKS?cid=website_cta_psi" -ForegroundColor Cyan
        Write-Host ""
        if (Confirm-Tecla 'Deseja realizar o download agora?') {

            $setupPath = "$env:USERPROFILE\Downloads\CodexSetup.exe"
            try {
                Write-Step "Baixando Codex Desktop..."
                $headers = @{ 'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36' }
                Invoke-WebRequest -Uri "https://get.microsoft.com/installer/download/9PLM9XGG6VKS?cid=website_cta_psi" `
                    -OutFile $setupPath -UseBasicParsing -Headers $headers -MaximumRedirection 10
                # Valida que e um executavel (MZ header)
                $bytes = [System.IO.File]::ReadAllBytes($setupPath)
                if ($bytes[0] -eq 77 -and $bytes[1] -eq 90) {
                    Write-Ok "Download concluido: $setupPath"
                    Write-Warn "Execute o arquivo para instalar o Codex Desktop."
                } else {
                    Remove-Item $setupPath -Force
                    Write-Fail "O arquivo baixado nao e valido. Acesse o link manualmente."
                }
            } catch {
                Write-Fail "Falha no download: $_"
            }
        }
        Pause-Readable 3
    }
}

# ============================================================
# 4b. OPENCODE DESKTOP
# ============================================================
if ($instalarOpenDesk) {

    Write-Step "Verificando OpenCode Desktop..."

    if ($wingetOk) {
        # Verifica se ja esta instalado via winget list (mais confiavel que upgrade)
        $openDesktopInstalled = $false
        try {
            $listOutput = & winget list --accept-source-agreements 2>&1 | Out-String
            if ($listOutput -match "SST.OpenCodeDesktop" -or $listOutput -match "OpenCode") {
                $openDesktopInstalled = $true
            }
        } catch { }

        if ($openDesktopInstalled) {
            Write-Ok "OpenCode Desktop ja esta instalado."
            Write-Step "Verificando atualizacoes..."
            try {
                & winget upgrade --id SST.OpenCodeDesktop --silent --accept-package-agreements --accept-source-agreements 2>&1 |
                    Where-Object { $_ -notmatch '^\s*[-\|/]\s*$' } |
                    ForEach-Object { if ($_.Trim()) { Write-Host $_ } }
                Write-Ok "OpenCode Desktop atualizado."
            } catch {
                Write-Warn "Nao foi possivel verificar atualizacoes: $_"
            }
            Pause-Readable 3
        } else {
            Write-Step "OpenCode Desktop nao encontrado. Instalando via winget..."
            try {
                & winget install --id SST.OpenCodeDesktop --silent --accept-package-agreements --accept-source-agreements 2>&1 |
                    Where-Object { $_ -notmatch '^\s*[-\|/]\s*$' } |
                    ForEach-Object { if ($_.Trim()) { Write-Host $_ } }
                Write-Ok "OpenCode Desktop instalado com sucesso."
                Write-Ok "Procure por 'OpenCode' no Menu Iniciar para abrir o app."
                Pause-Readable 3
            } catch {
                Write-Fail "Falha ao instalar OpenCode Desktop: $_"
                Write-Warn "Acesse: https://opencode.ai para instalar manualmente."
                Pause-Readable 4
            }
        }
    } else {
        Write-Warn "winget nao disponivel. Instale o OpenCode Desktop manualmente."
        Write-Host "  Acesse: https://opencode.ai" -ForegroundColor Cyan
        Pause-Readable 3
    }
}

# ============================================================
# 5. CODEX CLI (OpenAI) — npm i -g @openai/codex
# ============================================================
if ($instalarCodexCLI) {

    Write-Step "Verificando Codex CLI..."

    if (-not (Ensure-NodeJS -WingetOk $wingetOk)) {
        Write-Warn "Nao foi possivel garantir o Node.js. Pulando Codex CLI."
        Pause-Readable 3
    } else {
        try {
            Write-Step "Instalando/atualizando Codex CLI..."
            & npm install -g @openai/codex 2>&1 | ForEach-Object { Write-Host $_ }
            Write-Ok "Codex CLI instalado/atualizado com sucesso."
        } catch {
            Write-Fail "Falha na instalacao do Codex CLI: $_"
        }
        Pause-Readable 3
    }
}

# ============================================================
# 6. OPENCODE � via npm
# ============================================================
if ($instalarOpenCode) {
    Invoke-NpmTool -Label "OpenCode" -Cmd "opencode" -Package "opencode-ai" -NpmName "opencode-ai"
}

# ----------------------------------------------------------
# PATH: garantir diretorio e entrada no PATH do usuario
# (apenas quando ferramentas CLI foram selecionadas)
# ----------------------------------------------------------
$algumaCLI = $instalarGit -or $instalarClaudeCLI -or $instalarCodexCLI -or $instalarOpenCode

if ($algumaCLI) {
    $targetDir = "$env:USERPROFILE\.local\bin"

    Write-Step "Verificando diretorio $targetDir..."
    if (-not (Test-Path $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        Write-Ok "Diretorio criado: $targetDir"
    } else {
        Write-Ok "Diretorio ja existe: $targetDir"
    }

    # Diretorios que precisam estar no PATH para CMD e PowerShell
    $pathDirs = @(
        $targetDir,                        # %USERPROFILE%\.local\bin
        "$env:APPDATA\npm",               # executaveis instalados pelo npm (codex, opencode, claude)
        "$env:ProgramFiles\nodejs"        # node e npm do sistema
    )

    Write-Step "Verificando e corrigindo PATH..."
    $null = Test-And-Fix-Path
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $pathAtualizado = $false

    foreach ($dir in $pathDirs) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        $jaExiste = ($currentPath -split ";") | Where-Object { $_ -ieq $dir }
        if (-not $jaExiste) {
            $currentPath = ($currentPath.TrimEnd(";") + ";" + $dir).TrimStart(";")
            Write-Ok "Adicionado ao PATH: $dir"
            $pathAtualizado = $true
        } else {
            Write-Ok "Ja no PATH: $dir"
        }
    }

    if ($pathAtualizado) {
        [Environment]::SetEnvironmentVariable("Path", $currentPath, "User")
        Write-Ok "PATH do usuario atualizado com sucesso."
        Write-Warn "Abra um novo CMD ou PowerShell para que as alteracoes tenham efeito."
        Pause-Readable 3
    }

    # Atualiza PATH na sessao atual (PowerShell corrente)
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + $currentPath
}

# ----------------------------------------------------------
# VERIFICACAO FINAL
# ----------------------------------------------------------
$algumInstalado = $false

if ($instalarGit -and $gitCmdExe -and (Test-Path $gitCmdExe)) {
    try   { $v = & $gitCmdExe --version 2>&1; Write-Ok "Git Bash       : $v"; $algumInstalado = $true }
    catch { Write-Warn "Git Bash nao detectado. Tente reabrir o terminal." }
}

if ($instalarClaudeCLI) {
    try   { $v = & claude --version 2>&1; Write-Ok "Claude Code    : $(($v | Out-String).Trim())"; $algumInstalado = $true }
    catch { Write-Warn "Claude Code nao detectado. Tente reabrir o terminal." }
}

if ($instalarCodexCLI) {
    try   { $v = & codex --version 2>&1; Write-Ok "Codex CLI      : $(($v | Out-String).Trim())"; $algumInstalado = $true }
    catch { Write-Warn "Codex CLI nao detectado. Tente reabrir o terminal." }
}

if ($instalarOpenCode) {
    try   { $v = & opencode --version 2>&1; Write-Ok "OpenCode       : $(($v | Out-String).Trim())"; $algumInstalado = $true }
    catch { Write-Warn "OpenCode nao detectado. Tente reabrir o terminal." }
}

if ($instalarClaudeDesk) {
    $pkg = Get-AppxPackage -Name "*Claude*" -ErrorAction SilentlyContinue
    if ($pkg) {
        Write-Ok "Claude Desktop : instalado (versao $($pkg.Version))."
        $algumInstalado = $true
    } elseif ($wingetOk) {
        Write-Warn "Claude Desktop : nao detectado. Tente pesquisar no Menu Iniciar ou reinstalar."
    }
    # Sem winget: usuario ja foi orientado durante a instalacao
}

if ($instalarCodexDesk) {
    if ($codexDesktopOk) {
        Write-Ok "Codex Desktop  : instalado com sucesso."
        $algumInstalado = $true
    } elseif ($wingetOk) {
        Write-Warn "Codex Desktop  : nao detectado. Tente pesquisar no Menu Iniciar ou reinstalar."
    }
}

if ($instalarOpenDesk) {
    $openPkg = $null
    try { $openPkg = & winget list --id SST.OpenCodeDesktop 2>&1 | Out-String } catch { }
    if ($openPkg -match "SST.OpenCodeDesktop") {
        Write-Ok "OpenCode Desktop: instalado com sucesso."
        $algumInstalado = $true
    } elseif ($wingetOk) {
        Write-Warn "OpenCode Desktop: nao detectado. Tente pesquisar no Menu Iniciar ou reinstalar."
    }
}

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "  Concluido!" -ForegroundColor Green

$temCLI     = $instalarGit -or $instalarClaudeCLI -or $instalarCodexCLI -or $instalarOpenCode
$temDesktop = $instalarClaudeDesk -or $instalarCodexDesk -or $instalarOpenDesk

if ($algumInstalado) {
    if ($temCLI -and $temDesktop) {
        Write-Host "  - CLI: Abra um novo terminal para usar os comandos." -ForegroundColor Green
        Write-Host "  - Desktop: Pesquise os apps no Menu Iniciar." -ForegroundColor Green
    } elseif ($temCLI) {
        Write-Host "  Abra um novo terminal para usar as ferramentas instaladas." -ForegroundColor Green
    } elseif ($temDesktop) {
        Write-Host "  Pesquise os apps instalados no Menu Iniciar." -ForegroundColor Green
    }
}
Write-Host "============================================================`n" -ForegroundColor Cyan

} catch {
    Write-Host "`n[ERR] Ocorreu um erro inesperado: $_" -ForegroundColor Red
}

Write-Host ""
if (-not (Confirm-Tecla "Voltar ao menu?")) {
    Write-Host "`nSaindo..." -ForegroundColor Gray
    break
}

} while ($true)

} catch {
    Write-Host "`n[ERR] Erro fatal: $_" -ForegroundColor Red
    Write-Host "[ERR] Linha: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
    Write-Host ""
    Read-Host "Pressione ENTER para fechar"
}