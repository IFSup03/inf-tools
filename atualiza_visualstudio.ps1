
param(
    [string]$WorkDir = "C:\ProgramData\VSUpdater",
    [ValidateSet("2022", "2026", "All")]
    [string]$Year    = "All",
    [ValidateSet("Community", "Professional", "Enterprise", "BuildTools")]
    [string]$Edition = "Community",
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$script:ExitCode       = 0


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
        $wtArgs = @('-w', '-1', '--size', '140,42', 'new-tab', '--title', 'atualiza_visualstudio', '--suppressApplicationTitle', '--', $shellPath, '-NoExit') + $argList
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

$TempDir = Join-Path $WorkDir "Temp"

[void](New-Item -ItemType Directory -Path $TempDir -Force)

# Mapeamento de edições: Product ID e sufixo do bootstrapper
$EditionMap = @{
    "Community"    = @{ ProductID = "Microsoft.VisualStudio.Product.Community";    Bootstrapper = "vs_community.exe"    }
    "Professional" = @{ ProductID = "Microsoft.VisualStudio.Product.Professional"; Bootstrapper = "vs_professional.exe" }
    "Enterprise"   = @{ ProductID = "Microsoft.VisualStudio.Product.Enterprise";   Bootstrapper = "vs_enterprise.exe"   }
    "BuildTools"   = @{ ProductID = "Microsoft.VisualStudio.Product.BuildTools";   Bootstrapper = "vs_buildtools.exe"   }
}

$SelectedEdition = $EditionMap[$Edition]
$ProductID       = $SelectedEdition.ProductID
$BootstrapperExe = $SelectedEdition.Bootstrapper

# Bootstrappers oficiais por canal/ano
# VS 2022 = canal 17 (Release) | VS 2026 = canal 18 (Stable)
$BootstrapperMap = @{
    "2022" = "https://aka.ms/vs/17/release/$BootstrapperExe"
    "2026" = "https://aka.ms/vs/18/Stable/$BootstrapperExe"
}

# ──────────────────────────────────────────────────────────────────────────────
# Funções auxiliares
# ──────────────────────────────────────────────────────────────────────────────

function Write-Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Write-Host $line
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
    param([string]$Path, [int]$DaysToKeep = 60)

    if (-not (Test-Path $Path)) { return }

    $limit = (Get-Date).AddDays(-$DaysToKeep)
    Get-ChildItem -Path $Path -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -eq ".log" -and $_.LastWriteTime -lt $limit } |
        ForEach-Object {
            try {
                Remove-Item $_.FullName -Force -ErrorAction Stop
                Write-Log "Log antigo removido: $($_.FullName)"
            }
            catch {
                Write-Log "Falha ao remover log antigo: $($_.FullName) | $($_.Exception.Message)"
            }
        }
}

function Get-InstalledVSInstances {
    <#
        Usa vswhere.exe para descobrir instâncias instaladas da edição selecionada.
        Retorna lista de objetos com Year, Version e InstallPath.
    #>
    $result      = @()
    $vswherePath = "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe"

    if (-not (Test-Path $vswherePath)) {
        Write-Log "vswhere.exe não encontrado. Não é possível detectar instâncias instaladas."
        return $result
    }

    $instances = & $vswherePath -products $ProductID -all -format json 2>$null | ConvertFrom-Json

    foreach ($inst in $instances) {
        $rawVersion = $inst.installationVersion

        $major = try { ([version]$rawVersion).Major } catch { $null }
        $vsYear = switch ($major) {
            17      { "2022" }
            18      { "2026" }
            default { $null  }
        }

        if (-not $vsYear) {
            Write-Log "Instância ignorada (versão principal não reconhecida): $rawVersion"
            continue
        }

        try {
            $result += [PSCustomObject]@{
                Year        = $vsYear
                Version     = [version]$rawVersion
                InstallPath = $inst.installationPath
            }
            Write-Log "Encontrado: Visual Studio $vsYear $Edition | Versão: $rawVersion | Caminho: $($inst.installationPath)"
        }
        catch {
            Write-Log "Não foi possível converter a versão '$rawVersion'. Instância ignorada."
        }
    }

    return $result
}

function Get-BootstrapperVersion {
    <#
        Tenta obter a versão disponível do bootstrapper SEM fazer download completo.
        Faz um download parcial (1 MB) e lê os metadados PE do arquivo.
        Retorna [version] ou $null se não conseguir.
    #>
    param([string]$Url, [string]$Label)

    $partialPath = Join-Path $TempDir ("vs_partial_{0}.exe" -f [System.IO.Path]::GetRandomFileName())

    try {
        Write-Log "[$Label] Verificando versão disponível via download parcial (1 MB)..."

        $request        = [System.Net.HttpWebRequest]::Create($Url)
        $request.Method = "GET"
        $request.AddRange("bytes", 0, 1048575)
        $request.Timeout = 30000

        $response = $request.GetResponse()
        $stream   = $response.GetResponseStream()
        $buffer   = New-Object byte[] 1048576
        $read     = 0

        $fs = [System.IO.File]::Create($partialPath)
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
            $m = [regex]::Match($rawVersion, '\d+\.\d+\.\d+\.\d+')
            if ($m.Success) {
                Write-Log "[$Label] Versão disponível (download parcial): $($m.Value)"
                return [version]$m.Value
            }
        }

        Write-Log "[$Label] Download parcial não retornou versão legível nos metadados."
    }
    catch {
        Write-Log "[$Label] Falha no download parcial: $($_.Exception.Message)"
    }
    finally {
        if (Test-Path $partialPath) {
            Remove-Item $partialPath -Force -ErrorAction SilentlyContinue
        }
    }

    return $null
}

function Stop-VisualStudio {
    param([string]$Label)

    $vsProcesses = @("devenv", "WDExpress", "VSIXInstaller")
    $found       = $false

    foreach ($procName in $vsProcesses) {
        $running = Get-Process -Name $procName -ErrorAction SilentlyContinue
        if ($running) {
            Write-Log "[$Label] Encerrando processo '$procName'..."
            $running | Stop-Process -Force
            $found = $true
        }
    }

    if ($found) {
        Start-Sleep -Seconds 5
    }
}

function Wait-VSInstallerIdle {
    param([string]$Label, [int]$TimeoutMinutes = 30)
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    $processNames = @('setup','vs_installer','vs_installershell','VSIXInstaller')
    while ($true) {
        $running = Get-Process -ErrorAction SilentlyContinue | Where-Object {
            $processNames -contains $_.Name -and $_.Id -ne $PID -and ($_.Name -eq 'VSIXInstaller' -or ($_.Path -and $_.Path -match 'Microsoft Visual Studio|VisualStudio|Installer'))
        }
        if (-not $running) { return $true }
        if ((Get-Date) -gt $deadline) {
            $names = ($running | Select-Object -ExpandProperty Name -Unique) -join ', '
            throw "Visual Studio Installer ainda esta em execucao/configuracao apos $TimeoutMinutes minuto(s): $names"
        }
        $names = ($running | Select-Object -ExpandProperty Name -Unique) -join ', '
        Write-Log "[$Label] Aguardando Visual Studio Installer finalizar configuracao em andamento: $names"
        Start-Sleep -Seconds 10
    }
}


function Update-VSInstance {
    param(
        [string]$Year,
        [version]$InstalledVersion,
        [string]$InstallPath
    )

    $label            = "VS $Year $Edition"
    $bootstrapperUrl  = $BootstrapperMap[$Year]
    $bootstrapperPath = Join-Path $TempDir ("vs_${Edition}_${Year}.exe")

    try {
        # 1. Verifica versão disponível via download parcial
        $availableVersion = Get-BootstrapperVersion -Url $bootstrapperUrl -Label $label

        if ($availableVersion) {
            if (-not $Force -and $InstalledVersion -and $availableVersion -le $InstalledVersion) {
                Write-Log "[$label] Já está na versão mais recente ($InstalledVersion). Nenhuma atualização necessária."
                return $true
            }
        }
        else {
            Write-Log "[$label] AVISO: Não foi possível verificar versão antes do download. Prosseguindo com download completo."
        }

        # 2. Baixa o bootstrapper completo
        Write-Log "[$label] Baixando bootstrapper..."
        Invoke-WebRequest -Uri $bootstrapperUrl -OutFile $bootstrapperPath -UseBasicParsing

        # 3. Confirma versão pelo arquivo baixado
        $item       = Get-Item $bootstrapperPath -ErrorAction Stop
        $rawVersion = $item.VersionInfo.ProductVersion
        if (-not $rawVersion) { $rawVersion = $item.VersionInfo.FileVersion }

        if ($rawVersion) {
            $m = [regex]::Match($rawVersion, '\d+\.\d+\.\d+\.\d+')
            if ($m.Success) {
                $downloadedVersion = [version]$m.Value
                Write-Log "[$label] Versão do bootstrapper baixado: $downloadedVersion"

                if (-not $Force -and $InstalledVersion -and $downloadedVersion -le $InstalledVersion) {
                    Write-Log "[$label] Já está na versão mais recente ($InstalledVersion). Nenhuma atualização necessária (confirmado após download)."
                    return $true
                }
            }
        }

        # 4. Fecha o VS se estiver aberto
        Stop-VisualStudio -Label $label

        # 5. Atualiza o VS Installer antes do produto
        $vsInstallerSetup = "C:\Program Files (x86)\Microsoft Visual Studio\Installer\setup.exe"
        if (Test-Path $vsInstallerSetup) {
            Write-Log "[$label] Atualizando VS Installer..."
            $installerUpdateArgs = "update --quiet --norestart --installPath `"$InstallPath`""
            Wait-VSInstallerIdle -Label $label | Out-Null
            $procInst = Invoke-SilentProcess -FilePath $vsInstallerSetup -ArgumentList $installerUpdateArgs
            if ($procInst.ExitCode -ne 0 -and $procInst.ExitCode -ne 3010) { throw "Falha ao atualizar Visual Studio Installer. ExitCode: $($procInst.ExitCode)" }
            Wait-VSInstallerIdle -Label $label | Out-Null
            Write-Log "[$label] VS Installer ExitCode: $($procInst.ExitCode)"
        }

        # 6. Executa a atualização do produto
        $arguments  = "update --wait --quiet --norestart --installPath `"$InstallPath`""

        Write-Log "[$label] Executando atualização silenciosa..."
        $proc = Invoke-SilentProcess -FilePath $bootstrapperPath -ArgumentList $arguments

        Write-Log "[$label] ExitCode do instalador: $($proc.ExitCode)"

        # 3010 = sucesso com reinicialização pendente (comportamento normal do Windows Installer)
        if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne 3010) {
            throw "Falha na instalação. ExitCode: $($proc.ExitCode)."
        }

        if ($proc.ExitCode -eq 3010) {
            Write-Log "[$label] Atualização concluída. Reinicialização pendente."
        }
        else {
            Write-Log "[$label] Atualização concluída com sucesso."
        }

        return $true
    }
    catch {
        Write-Log "[$label] ERRO: $($_.Exception.Message)"
        return $false
    }
    finally {
        if (Test-Path $bootstrapperPath) {
            Remove-Item $bootstrapperPath -Force -ErrorAction SilentlyContinue
            Write-Log "[$label] Bootstrapper temporário removido."
        }
    }
}

# ──────────────────────────────────────────────────────────────────────────────
# Execução principal
# ──────────────────────────────────────────────────────────────────────────────

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    Write-Log "===== Início da execução ====="
    Write-Log "Parâmetros: Year=$Year | Edition=$Edition | Force=$Force"


    $instances = Get-InstalledVSInstances

    if ($instances.Count -eq 0) {
        Write-Log "Nenhuma instância do Visual Studio $Edition encontrada. Encerrando."
        Write-Log "===== Fim da execução ====="
        exit 0
    }

    $yearsToProcess = if ($Year -eq "All") { @("2022", "2026") } else { @($Year) }
    $anyFailure     = $false

    foreach ($vsYear in $yearsToProcess) {
        $inst = $instances | Where-Object { $_.Year -eq $vsYear }

        if (-not $inst) {
            Write-Log "[VS $vsYear $Edition] Não instalado. Pulando."
            continue
        }

        $success = Update-VSInstance `
            -Year             $inst.Year `
            -InstalledVersion $inst.Version `
            -InstallPath      $inst.InstallPath

        if (-not $success) {
            $anyFailure = $true
        }
    }

    if ($anyFailure) { $script:ExitCode = 1 }

    Write-Log "===== Fim da execução ====="
}
catch {
    Write-Log "ERRO GERAL: $($_.Exception.Message)"
    Write-Log "===== Fim com erro ====="
    $script:ExitCode = 1
}

exit $script:ExitCode
