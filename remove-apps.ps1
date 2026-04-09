<#
.SYNOPSIS
    Remove aplicativos indesejados do Windows e bloqueia a reinstalação automática.

.DESCRIPTION
    Permite ao usuário escolher quais aplicativos pré-instalados do Windows deseja remover.
    Remove pacotes provisionados para novos usuários e instalados para usuários existentes.
    Aplica política via registro para bloquear reinstalação automática.
    Solicita elevação automática se necessário, conforme configuração.

.NOTES
    Autor       : Victor Hugo Gomides
    Data criação: 2025-05-07
    Última modif: 2025-05-07
    Versão      : 1.1
    RequerAdmin : "sim"
#>

# =================== VARIÁVEIS CONFIGURÁVEIS ===================
#region Variáveis Configuráveis
<#
.SYNOPSIS
    Variáveis configuráveis para controle do comportamento do script.
#>

# Define se o script deve solicitar elevação administrativa ("sim" ou "não")
$RequerAdmin = "sim"

# Caminho do arquivo de log
$LogPath = "$PSScriptRoot\removedor_apps.log"


# Mapeamento das opções de aplicativos para remoção
$applicationsMap = @{
    "1" = @{ Name = "Xbox (Game Bar, Xbox Console Companion, Identidade Xbox, Gaming Overlay)"; Apps = @(
        "Microsoft.XboxGameOverlay",
        "Microsoft.Xbox.TCUI",
        "Microsoft.XboxGamingOverlay",
        "Microsoft.XboxIdentityProvider",
        "Microsoft.GamingApp",
        "Microsoft.XboxApp"
    )}
    "2" = @{ Name = "Outlook (Versão Microsoft Store)"; Apps = @("Microsoft.OutlookForWindows") }
    "3" = @{ Name = "OneDrive (Remoção completa do cliente OneDrive)"; Apps = @("Microsoft.OneDriveSync") }
    "4" = @{ Name = "Aplicativos Padrão (OneNote, Paint 3D, Skype, Seu Telefone, Feedback Hub, Clima, Solitaire)"; Apps = @(
        "Microsoft.Office.OneNote",
        "Microsoft.MSPaint",
        "Microsoft.SkypeApp",
        "Microsoft.YourPhone",
        "Microsoft.MixedReality.Portal",
        "Microsoft.WindowsFeedbackHub",
        "Microsoft.BingWeather",
        "Microsoft.MicrosoftSolitaireCollection"
    )}
    "5" = @{ Name = "Cortana (Assistente virtual da Microsoft)"; Apps = @("Microsoft.549981C3F5F10") }
    "6" = @{ Name = "Fotos, Filmes e TV, Mapas (Aplicativos de mídia e navegação)"; Apps = @(
        "Microsoft.ZuneVideo",
        "Microsoft.Windows.Photos",
        "Microsoft.WindowsMaps"
    )}
    "7" = @{ Name = "Copilot (Assistente integrado do Windows)"; Apps = @("Microsoft.Copilot") }
    "8" = @{ Name = "Email e Microsoft 365 (Aplicativos de e-mail e hub do Office)"; Apps = @(
        "microsoft.windowscommunicationsapps",
        "Microsoft.MicrosoftOfficeHub"
    )}
    "9" = @{ Name = "Outros Aplicativos (Ajuda, Câmera, Relógio, Visualizador 3D, Gravador de Voz)"; Apps = @(
        "Microsoft.GetHelp",
        "Microsoft.WindowsCamera",
        "Microsoft.WindowsAlarms",
        "Microsoft.Microsoft3DViewer",
        "Microsoft.WindowsSoundRecorder"
    )}
    "10" = @{ Name = "Notas Autoadesivas (Sticky Notes)"; Apps = @("Microsoft.MicrosoftStickyNotes") }
    "11" = @{ Name = "Reprodutor Multimídia (Zune Music, Windows Media Player)"; Apps = @(
        "Microsoft.ZuneMusic",
        "Microsoft.WebMediaExtensions",
        "Microsoft.VP9VideoExtensions"
    )}
}
#endregion

# =================== SOLICITAÇÃO DE PRIVILÉGIO ===================
#region Solicitação de Privilégio Administrativo
<#
.SYNOPSIS
    Verifica privilégios administrativos e solicita elevação se necessário.
#>

if ($RequerAdmin -notin @("sim", "não")) {
    Write-Warning "Valor inválido para 'RequerAdmin'. Use 'sim' ou 'não'."
    exit 1
}

if ($RequerAdmin -eq "sim") {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "Este script requer privilégios administrativos. Solicitando elevação..." -ForegroundColor Yellow
        try {
            $process = Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -PassThru -ErrorAction Stop
            $process.WaitForExit()
            exit $process.ExitCode
        }
        catch {
            Write-Host "Elevação cancelada pelo usuário. Encerrando..." -ForegroundColor Red
            exit 1
        }
    }
}
#endregion

# =================== FUNÇÕES ===================
#region Funções

<#
.SYNOPSIS
    Registra mensagens no console e arquivo de log com timestamp e nível.
.PARAMETER Message
    Mensagem a ser registrada.
.PARAMETER Level
    Nível da mensagem: INFO, WARN, ERROR. Padrão é INFO.
#>
function Write-Log {
    param (
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    switch ($Level.ToUpper()) {
        "INFO"  { Write-Host "[$timestamp] [INFO]  $Message" -ForegroundColor Cyan }
        "WARN"  { Write-Host "[$timestamp] [WARN]  $Message" -ForegroundColor Yellow }
        "ERROR" { Write-Host "[$timestamp] [ERROR] $Message" -ForegroundColor Red }
    }
    Add-Content -Path $LogPath -Value "[$timestamp] [$Level] $Message" -Encoding UTF8
}

#endregion

# =================== BLOCO PRINCIPAL ===================
#region Bloco Principal

Clear-Host
Write-Log "Bem-vindo ao removedor de aplicativos!"

Write-Host ""
Write-Host "Escolha quais aplicativos deseja remover digitando os números separados por vírgula."
Write-Host ""

foreach ($key in ($applicationsMap.Keys | ForEach-Object {[int]$_} | Sort-Object)) {
    Write-Host "$key - $($applicationsMap[$key.ToString()].Name)"
}
Write-Host "12 - Remover Tudo"
Write-Host "0 - Cancelar"
Write-Host ""

do {
    $userInput = Read-Host "Digite os números das opções desejadas (exemplo: 1,3,4) ou 0 para cancelar"

    if ($userInput -eq "0") {
        Write-Log "Operação cancelada pelo usuário." "WARN"
        Exit
    }

    if ($userInput -match '^(\s*(1[0-2]|[1-9])\s*,)*\s*(1[0-2]|[1-9])\s*$') {
        $selections = $userInput -split "," | ForEach-Object { $_.Trim() } | Sort-Object -Unique
        $invalidSelections = $selections | Where-Object { ($_ -ne '12') -and (-not $applicationsMap.ContainsKey($_)) }
        if ($invalidSelections.Count -eq 0) {
            break
        }
        else {
            Write-Log "Opções inválidas detectadas: $($invalidSelections -join ', '). Tente novamente." "ERROR"
        }
    }
    else {
        Write-Log "Formato inválido. Digite números entre 1 e 12 separados por vírgula. Exemplo: 1,3,4" "ERROR"
    }
} while ($true)

$appsToRemove = @()
if ($selections -contains "12") {
    foreach ($item in $applicationsMap.Values) {
        $appsToRemove += $item.Apps
    }
} else {
    foreach ($sel in $selections) {
        $appsToRemove += $applicationsMap[$sel].Apps
    }
}

Write-Log "Iniciando remoção dos aplicativos selecionados..."

# Obter listas completas uma vez para otimizar
$allProvisionedPackages = Get-AppxProvisionedPackage -Online
$allInstalledPackages = Get-AppxPackage -AllUsers

foreach ($app in $appsToRemove | Sort-Object -Unique) {
    try {
        Write-Log "Processando aplicativo: $app"

        $provisioned = $allProvisionedPackages | Where-Object { $_.PackageName -like "*$app*" }
        if ($provisioned) {
            foreach ($pkg in $provisioned) {
                try {
                    Remove-AppxProvisionedPackage -Online -PackageName $pkg.PackageName -ErrorAction Stop
                    Write-Log "Pacote provisionado removido: $($pkg.PackageName)"
                }
                catch {
                    Write-Log "Erro ao remover pacote provisionado $($pkg.PackageName): $_" "ERROR"
                }
            }
        }
        else {
            Write-Log "Nenhum pacote provisionado encontrado para $app"
        }

        $installed = $allInstalledPackages | Where-Object { $_.Name -like "*$app*" }
        if ($installed) {
            foreach ($pkg in $installed) {
                try {
                    Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
                    Write-Log "Aplicativo removido: $($pkg.Name)"
                }
                catch {
                    Write-Log "Erro ao remover aplicativo $($pkg.Name): $_" "ERROR"
                }
            }
        }
        else {
            Write-Log "Aplicativo não instalado para usuários existentes: $app"
        }
    }
    catch {
        Write-Log "Erro geral ao processar ${app}: $_" "ERROR"
    }
}

Write-Log "Remoção finalizada!"

#endregion

# =================== BLOQUEIO DE REINSTALAÇÃO AUTOMÁTICA ===================
#region Bloqueio de reinstalação automática via registro

Write-Log "Bloqueando reinstalação automática de aplicativos..."
$regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
try {
    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
        Write-Log "Criado caminho de registro: $regPath"
    }
    Set-ItemProperty -Path $regPath -Name "DisableWindowsConsumerFeatures" -Value 1 -Type DWord -ErrorAction Stop
    Write-Log "Reinstalação automática desativada com sucesso."
}
catch {
    Write-Log "Erro ao configurar registro para bloqueio de reinstalação: $_" "ERROR"
}

#endregion

Write-Log "Script finalizado. Aguarde 3 segundos antes de fechar."
Start-Sleep -Seconds 3
