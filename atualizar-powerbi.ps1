#requires -RunAsAdministrator

param(
    [string]$WorkDir = "C:\ProgramData\PowerBIUpdater",
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$script:ExitCode = 0
$script:DeleteInstallerAtEnd = $false

$DownloadDetailsUrl = "https://www.microsoft.com/en-us/download/details.aspx?id=58494"
$LogDir             = Join-Path $WorkDir "Logs"
$TempDir            = Join-Path $WorkDir "Temp"
$InstallerPath      = Join-Path $TempDir "PBIDesktopSetup_x64.exe"
$RunLog             = Join-Path $LogDir ("Run-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))

[void](New-Item -ItemType Directory -Path $LogDir -Force)
[void](New-Item -ItemType Directory -Path $TempDir -Force)

function Write-Log {
    param([string]$Message)

    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Add-Content -Path $RunLog -Value $line
    Write-Host $line
}

function Remove-OldLogs {
    param(
        [string]$Path,
        [int]$DaysToKeep = 60
    )

    if (-not (Test-Path $Path)) {
        return
    }

    $limitDate = (Get-Date).AddDays(-$DaysToKeep)

    $oldLogs = Get-ChildItem -Path $Path -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Extension -eq ".log" -and $_.LastWriteTime -lt $limitDate
        }

    foreach ($log in $oldLogs) {
        try {
            Remove-Item -Path $log.FullName -Force -ErrorAction Stop
            Write-Log "Log antigo removido: $($log.FullName)"
        }
        catch {
            Write-Log "Falha ao remover log antigo: $($log.FullName) | $($_.Exception.Message)"
        }
    }
}

function Get-InstalledPowerBIVersion {
    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $apps = Get-ItemProperty -Path $paths -ErrorAction SilentlyContinue |
        Where-Object {
            $_.DisplayName -match "Power BI Desktop" -and
            $_.DisplayName -notmatch "Report Server"
        }

    if (-not $apps) {
        return $null
    }

    $app = $apps |
        Sort-Object {
            try { [version]$_.DisplayVersion } catch { [version]"0.0.0.0" }
        } -Descending |
        Select-Object -First 1

    try {
        return [version]$app.DisplayVersion
    }
    catch {
        Write-Log "Não foi possível converter a versão instalada '$($app.DisplayVersion)'."
        return $null
    }
}

function Get-LatestInstallerUrl {
    Write-Log "Consultando página oficial de download..."
    $resp = Invoke-WebRequest -Uri $DownloadDetailsUrl -UseBasicParsing

    $matches = [regex]::Matches(
        $resp.Content,
        'https://download\.microsoft\.com/download/[^\s"''<>]+/PBIDesktopSetup_x64\.exe'
    )

    if ($matches.Count -eq 0) {
        throw "Não foi possível localizar a URL oficial do instalador na página de download."
    }

    $url = ($matches | ForEach-Object { $_.Value } | Select-Object -Unique | Select-Object -First 1).Trim()
    return [string]$url
}

function Get-LatestVersionFromUrl {
    param([string]$Url)

    # 1ª tentativa: extrair versão diretamente do caminho da URL
    $m = [regex]::Match($Url, '/(\d+\.\d+\.\d+\.\d+)/')
    if ($m.Success) {
        try {
            Write-Log "Versão extraída da URL: $($m.Groups[1].Value)"
            return [version]$m.Groups[1].Value
        }
        catch {
            Write-Log "Não foi possível converter a versão extraída da URL: $($m.Groups[1].Value)"
        }
    }

    # 2ª tentativa: download parcial (só o 1º MB) para ler metadados do PE sem baixar tudo
    Write-Log "Versão não encontrada na URL. Baixando apenas os primeiros 1 MB para verificar versão..."
    $partialPath = Join-Path $TempDir "PBIDesktop_partial.exe"
    try {
        $request = [System.Net.HttpWebRequest]::Create($Url)
        $request.Method = "GET"
        $request.AddRange("bytes", 0, 1048575)   # primeiros 1 MB
        $request.Timeout = 30000

        $response = $request.GetResponse()
        $stream   = $response.GetResponseStream()
        $buffer   = New-Object byte[] 1048576
        $read     = 0
        $fs       = [System.IO.File]::Create($partialPath)

        do {
            $chunk = $stream.Read($buffer, $read, $buffer.Length - $read)
            $read += $chunk
        } while ($chunk -gt 0 -and $read -lt $buffer.Length)

        $fs.Write($buffer, 0, $read)
        $fs.Close()
        $stream.Close()
        $response.Close()

        $item       = Get-Item $partialPath -ErrorAction Stop
        $rawVersion = $item.VersionInfo.ProductVersion
        if (-not $rawVersion) { $rawVersion = $item.VersionInfo.FileVersion }

        if ($rawVersion) {
            $mv = [regex]::Match($rawVersion, '\d+\.\d+\.\d+\.\d+')
            if ($mv.Success) {
                Write-Log "Versão obtida via download parcial: $($mv.Value)"
                return [version]$mv.Value
            }
        }

        Write-Log "Download parcial não retornou versão legível nos metadados."
    }
    catch {
        Write-Log "Falha no download parcial: $($_.Exception.Message)"
    }
    finally {
        if (Test-Path $partialPath) {
            Remove-Item $partialPath -Force -ErrorAction SilentlyContinue
        }
    }

    return $null
}

function Get-FileVersion {
    param([string]$Path)

    $item = Get-Item $Path -ErrorAction Stop
    $rawVersion = $item.VersionInfo.ProductVersion

    if (-not $rawVersion) {
        $rawVersion = $item.VersionInfo.FileVersion
    }

    if (-not $rawVersion) {
        throw "Não foi possível obter a versão do arquivo: $Path"
    }

    $m = [regex]::Match($rawVersion, '\d+\.\d+\.\d+\.\d+')
    if (-not $m.Success) {
        throw "Versão inválida no arquivo: $rawVersion"
    }

    return [version]$m.Value
}

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    Write-Log "===== Início da execução ====="

    Remove-OldLogs -Path $LogDir -DaysToKeep 60

    $installedVersion = Get-InstalledPowerBIVersion
    if ($installedVersion) {
        Write-Log "Versão instalada: $installedVersion"
    }
    else {
        Write-Log "Power BI Desktop não encontrado no registro."
    }

    $installerUrl = Get-LatestInstallerUrl
    Write-Log "URL do instalador encontrada: $installerUrl"

    # Verifica a versão disponível ANTES de baixar o instalador completo
    $latestVersion = Get-LatestVersionFromUrl -Url $installerUrl

    if ($latestVersion) {
        Write-Log "Versão disponível: $latestVersion"

        if (-not $Force -and $installedVersion -and $latestVersion -le $installedVersion) {
            Write-Log "Versão instalada ($installedVersion) já é igual ou superior à disponível ($latestVersion). Nenhuma atualização necessária."
            Write-Log "===== Fim da execução ====="
            $script:ExitCode = 0
            exit $script:ExitCode
        }
    }
    else {
        Write-Log "AVISO: Não foi possível determinar a versão antes do download. Prosseguindo com download completo para verificação."
    }

    Write-Log "Baixando instalador completo..."
    Invoke-WebRequest -Uri $installerUrl -OutFile $InstallerPath -UseBasicParsing

    # Confirma a versão pelo arquivo baixado
    $latestVersion = Get-FileVersion -Path $InstallerPath
    Write-Log "Versão confirmada do instalador baixado: $latestVersion"

    if (-not $Force -and $installedVersion -and $latestVersion -le $installedVersion) {
        Write-Log "Nenhuma atualização necessária (confirmado após download completo)."

        if (Test-Path $InstallerPath) {
            Remove-Item $InstallerPath -Force -ErrorAction SilentlyContinue
            Write-Log "Instalador temporário removido: $InstallerPath"
        }

        Write-Log "===== Fim da execução ====="
        $script:ExitCode = 0
        exit $script:ExitCode
    }

    $running = Get-Process -Name "PBIDesktop" -ErrorAction SilentlyContinue
    if ($running) {
        Write-Log "Power BI Desktop em execução. Encerrando processo..."
        $running | Stop-Process -Force
        Start-Sleep -Seconds 5
    }

    $installLog = Join-Path $LogDir ("Install-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
    $arguments = "-quiet -update -norestart ACCEPT_EULA=1 -log `"$installLog`""

    Write-Log "Executando atualização silenciosa..."
    $proc = Start-Process -FilePath $InstallerPath -ArgumentList $arguments -Wait -PassThru

    Write-Log "ExitCode do instalador: $($proc.ExitCode)"
    if ($proc.ExitCode -ne 0) {
        throw "Falha na instalação. Verifique o log: $installLog"
    }

    Start-Sleep -Seconds 10

    $newInstalledVersion = Get-InstalledPowerBIVersion
    if ($newInstalledVersion) {
        Write-Log "Versão após atualização: $newInstalledVersion"
    }
    else {
        Write-Log "Atualização concluída, mas não foi possível confirmar a versão no registro."
    }

    $script:DeleteInstallerAtEnd = $true

    Write-Log "===== Fim da execução ====="
    $script:ExitCode = 0
}
catch {
    Write-Log "ERRO: $($_.Exception.Message)"
    Write-Log "===== Fim com erro ====="
    $script:ExitCode = 1
}
finally {
    if ($script:DeleteInstallerAtEnd -and (Test-Path $InstallerPath)) {
        try {
            Remove-Item $InstallerPath -Force -ErrorAction Stop
            Write-Log "Instalador temporário removido: $InstallerPath"
        }
        catch {
            Write-Log "Falha ao remover instalador temporário: $($_.Exception.Message)"
        }
    }
}

exit $script:ExitCode