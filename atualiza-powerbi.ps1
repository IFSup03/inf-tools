
param(
    [string]$WorkDir = "C:\ProgramData\PowerBIUpdater",
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$script:ExitCode = 0
$script:DeleteInstallerAtEnd = $false

$DownloadDetailsUrl = "https://www.microsoft.com/en-us/download/details.aspx?id=58494"

function Test-IsAdmin {
    try {
        $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Quote-Argument {
    param([string]$Value)
    if ($null -eq $Value) { return '' }
    return '"' + ($Value -replace '"', '\"') + '"'
}

function Request-Elevation {
    $scriptPath = $PSCommandPath
    if (-not $scriptPath) { $scriptPath = $MyInvocation.PSCommandPath }
    if (-not $scriptPath) { $scriptPath = $MyInvocation.MyCommand.Path }
    if (-not $scriptPath) { throw 'Nao foi possivel localizar o caminho do script para elevar.' }

    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Quote-Argument $scriptPath))
    foreach ($pair in $PSBoundParameters.GetEnumerator()) {
        if ($pair.Value -is [switch] -or $pair.Value -is [bool]) {
            if ($pair.Value) { $argList += ('-' + $pair.Key) }
        } else {
            $argList += ('-' + $pair.Key)
            $argList += (Quote-Argument ([string]$pair.Value))
        }
    }

    $shellPath = (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source
    if (-not $shellPath) { $shellPath = (Get-Command powershell.exe -ErrorAction Stop).Source }

    $wtPath = $null
    try { $wtPath = (Get-Command wt.exe -ErrorAction Stop).Source } catch { }
    if (-not $wtPath) {
        $candidate = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\wt.exe'
        if (Test-Path -LiteralPath $candidate) { $wtPath = $candidate }
    }

    Write-Host ''
    Write-Host '  AVISO Este script requer privilegios administrativos.' -ForegroundColor Yellow
    Write-Host '  Solicitando elevacao via UAC...' -ForegroundColor Yellow

    if ($wtPath) {
        $wtArgs = @('-w', '-1', '--size', '140,42', 'new-tab', '--title', 'atualizar-powerbi', '--suppressApplicationTitle', '--', $shellPath, '-NoExit') + $argList
        Start-Process -FilePath $wtPath -Verb RunAs -ArgumentList $wtArgs -ErrorAction Stop | Out-Null
    } else {
        Start-Process -FilePath $shellPath -Verb RunAs -ArgumentList (('-NoExit'), $argList) -ErrorAction Stop | Out-Null
    }
    exit 0
}

if (-not (Test-IsAdmin)) {
    try { Request-Elevation }
    catch {
        Write-Host ('  ERRO Falha ao solicitar elevacao: ' + $_.Exception.Message) -ForegroundColor Red
        exit 1
    }
}

$TempDir            = Join-Path $WorkDir "Temp"
$InstallerPath      = Join-Path $TempDir "PBIDesktopSetup_x64.exe"

[void](New-Item -ItemType Directory -Path $TempDir -Force)

function Write-Log {
    param([string]$Message)

    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Write-Host $line
}


function Invoke-FastDownload {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$OutFile,
        [string]$Label = 'Download',
        [int]$BufferSize = 4194304,
        [int]$TimeoutSec = 900
    )

    try {
        Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue
    } catch { }

    $tempFile = "$OutFile.partial"
    if (Test-Path -LiteralPath $tempFile) { Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue }

    $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.AllowAutoRedirect = $true
    $client = New-Object System.Net.Http.HttpClient($handler)
    $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSec)
    try { $client.DefaultRequestHeaders.UserAgent.ParseAdd('InfinityUpdater/1.0') } catch { }

    $response = $null
    $source = $null
    $target = $null
    try {
        Write-Log "${Label}: iniciando download rapido..."
        $response = $client.GetAsync($Url, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        if (-not $response.IsSuccessStatusCode) {
            throw "HTTP $([int]$response.StatusCode) $($response.ReasonPhrase)"
        }

        $totalBytes = -1L
        try { if ($response.Content.Headers.ContentLength) { $totalBytes = [long]$response.Content.Headers.ContentLength } } catch { }
        $totalMb = if ($totalBytes -gt 0) { [Math]::Round($totalBytes / 1MB, 1) } else { 0 }
        if ($totalMb -gt 0) { Write-Log "${Label}: tamanho aproximado $totalMb MB" }

        $source = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $target = [System.IO.File]::Create($tempFile)
        $buffer = New-Object byte[] $BufferSize
        $readTotal = 0L
        $lastShown = Get-Date

        while ($true) {
            $read = $source.Read($buffer, 0, $buffer.Length)
            if ($read -le 0) { break }
            $target.Write($buffer, 0, $read)
            $readTotal += $read

            if (((Get-Date) - $lastShown).TotalSeconds -ge 3) {
                if ($totalBytes -gt 0) {
                    $pct = [Math]::Round(($readTotal / $totalBytes) * 100, 1)
                    $mb = [Math]::Round($readTotal / 1MB, 1)
                    Write-Log "${Label}: $pct% ($mb MB de $totalMb MB)"
                } else {
                    $mb = [Math]::Round($readTotal / 1MB, 1)
                    Write-Log "${Label}: $mb MB baixados"
                }
                $lastShown = Get-Date
            }
        }

        $target.Close(); $target = $null
        if (Test-Path -LiteralPath $OutFile) { Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue }
        Move-Item -LiteralPath $tempFile -Destination $OutFile -Force
        $finalMb = [Math]::Round((Get-Item -LiteralPath $OutFile).Length / 1MB, 1)
        Write-Log "${Label}: download concluido ($finalMb MB)."
        return $true
    } catch {
        if ($target) { try { $target.Close() } catch { } }
        if (Test-Path -LiteralPath $tempFile) { Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue }
        Write-Log "${Label}: download rapido falhou: $($_.Exception.Message)"
        return $false
    } finally {
        if ($source) { try { $source.Dispose() } catch { } }
        if ($target) { try { $target.Dispose() } catch { } }
        if ($response) { try { $response.Dispose() } catch { } }
        if ($client) { try { $client.Dispose() } catch { } }
        if ($handler) { try { $handler.Dispose() } catch { } }
    }
}
function Invoke-SilentProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string]$ArgumentList
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = $ArgumentList
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    [void]$proc.Start()
    $proc.StandardOutput.ReadToEnd() | Out-Null
    $proc.StandardError.ReadToEnd() | Out-Null
    $proc.WaitForExit()
    return [PSCustomObject]@{ ExitCode = $proc.ExitCode }
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
    if (-not (Invoke-FastDownload -Url $installerUrl -OutFile $InstallerPath -Label "Power BI")) { throw "Falha no download do instalador do Power BI." }

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

    $arguments = "-quiet -update -norestart ACCEPT_EULA=1"

    Write-Log "Executando atualização silenciosa..."
    $proc = Invoke-SilentProcess -FilePath $InstallerPath -ArgumentList $arguments

    Write-Log "ExitCode do instalador: $($proc.ExitCode)"
    if ($proc.ExitCode -ne 0) {
        throw "Falha na instalação. ExitCode: $($proc.ExitCode)."
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


