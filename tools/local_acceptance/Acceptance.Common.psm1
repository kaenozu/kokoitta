Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-ExternalCommand {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $command) { throw "Required command was not found: $Name" }
    return $command.Source
}

function New-AcceptanceRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$Root = '.acceptance'
    )
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $path = [System.IO.Path]::GetFullPath((Join-Path $Root "$Name-$stamp"))
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $path 'logs') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $path 'evidence') -Force | Out-Null
    return $path
}

function Enter-AcceptanceLock {
    [CmdletBinding()]
    param([string]$Root = '.acceptance')
    $lockRoot = [System.IO.Path]::GetFullPath($Root)
    New-Item -ItemType Directory -Path $lockRoot -Force | Out-Null
    $lockPath = Join-Path $lockRoot '.local-acceptance.lock'
    try {
        return [System.IO.File]::Open($lockPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    } catch {
        throw "Another local acceptance run appears active. Remove $lockPath only after confirming no Flutter, Gradle, emulator, or adb acceptance process is running."
    }
}

function Exit-AcceptanceLock {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Handle, [string]$Root = '.acceptance')
    $lockPath = Join-Path ([System.IO.Path]::GetFullPath($Root)) '.local-acceptance.lock'
    if ($Handle) { $Handle.Dispose() }
    Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
}

function Invoke-External {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$Arguments = @(),
        [string]$LogPath,
        [switch]$AllowFailure
    )
    $lines = @(& $FilePath @Arguments 2>&1 | ForEach-Object { "$_" })
    if ($LogPath) {
        $parent = Split-Path -Parent $LogPath
        if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        $lines | Set-Content -LiteralPath $LogPath -Encoding utf8
    }
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw "$FilePath exited with code $exitCode. See $LogPath"
    }
    [pscustomobject]@{ ExitCode = $exitCode; Lines = $lines }
}

function Invoke-Adb {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Serial,
        [Parameter(Mandatory)][string[]]$Arguments,
        [string]$LogPath,
        [switch]$AllowFailure
    )
    Invoke-External -FilePath (Assert-ExternalCommand adb) -Arguments (@('-s', $Serial) + $Arguments) -LogPath $LogPath -AllowFailure:$AllowFailure
}

function Wait-AndroidBoot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Serial, [int]$TimeoutSeconds = 240)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $result = Invoke-Adb -Serial $Serial -Arguments @('shell', 'getprop', 'sys.boot_completed') -AllowFailure
        if (($result.Lines -join '').Trim() -eq '1') { return }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)
    throw "Android device $Serial did not finish booting within $TimeoutSeconds seconds."
}

function Get-AppSandboxSnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Serial, [Parameter(Mandatory)][string]$PackageName)
    $script = 'cd /data/data/' + $PackageName + ' 2>/dev/null || exit 1; for d in files shared_prefs databases cache; do if [ -d "$d" ]; then find "$d" -type f 2>/dev/null; fi; done | sort | while IFS= read -r f; do s=$(wc -c < "$f" 2>/dev/null || echo 0); echo "$f|$s"; done'
    $result = Invoke-Adb -Serial $Serial -Arguments @('shell', 'run-as', $PackageName, 'sh', '-c', $script) -AllowFailure
    return @($result.Lines | Where-Object { $_ -match '\|' })
}

function Get-PendingDeletionManifestXml {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Serial, [Parameter(Mandatory)][string]$PackageName)
    # Flutter's shared_preferences Android backend uses this stable file name.
    # Reading it directly avoids losing the shell script's quoting through the
    # Windows PowerShell -> adb -> Android shell argument boundary.
    $result = Invoke-Adb -Serial $Serial -Arguments @(
        'shell',
        'run-as',
        $PackageName,
        'cat',
        'shared_prefs/FlutterSharedPreferences.xml'
    ) -AllowFailure
    if ($result.ExitCode -ne 0) { return $null }
    $xml = $result.Lines -join "`n"
    if ($xml -notmatch 'pendingDeletionManifestV1') { return $null }
    return $xml
}

function ConvertFrom-PendingDeletionManifestXml {
    [CmdletBinding()]
    param([AllowNull()][string]$XmlText)
    if ([string]::IsNullOrWhiteSpace($XmlText)) { return $null }
    $match = [regex]::Match($XmlText, '<string name="(?:flutter\.)?pendingDeletionManifestV1">(?<value>.*?)</string>', 'Singleline')
    if (-not $match.Success) { return $null }
    $decoded = [System.Net.WebUtility]::HtmlDecode($match.Groups['value'].Value)
    if ([string]::IsNullOrWhiteSpace($decoded)) { return $null }
    return ($decoded | ConvertFrom-Json -Depth 100)
}

function Test-AppPathExists {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Serial, [Parameter(Mandatory)][string]$PackageName, [Parameter(Mandatory)][string]$Path)
    $result = Invoke-Adb -Serial $Serial -Arguments @('shell', 'run-as', $PackageName, 'sh', '-c', 'test -e "$1"', 'sh', $Path) -AllowFailure
    return $result.ExitCode -eq 0
}

function Get-AppCrashSummary {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Serial, [Parameter(Mandatory)][string]$PackageName, [string]$LogPath)
    $result = Invoke-Adb -Serial $Serial -Arguments @('logcat', '-d', '-v', 'threadtime') -LogPath $LogPath -AllowFailure
    return @($result.Lines | Where-Object { $_ -match [regex]::Escape($PackageName) -and $_ -match 'FATAL EXCEPTION|ANR in|OutOfMemoryError|Fatal signal' })
}

function Write-AcceptanceReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Report,
        [Parameter(Mandatory)][string]$RunDirectory
    )
    $jsonPath = Join-Path $RunDirectory 'report.json'
    $mdPath = Join-Path $RunDirectory 'report.md'
    $Report | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $jsonPath -Encoding utf8
    $lines = @(
        "# $($Report.name)",
        '',
        "- Result: **$($Report.result)**",
        "- Started: $($Report.startedAt)",
        "- Finished: $($Report.finishedAt)",
        "- Repository HEAD: $($Report.repositoryHead)",
        "- Device: $($Report.device)",
        '',
        '## Checks'
    )
    foreach ($check in $Report.checks) {
        $lines += "- [$($check.status)] $($check.name): $($check.detail)"
    }
    $lines += @('', '## Evidence', "- JSON: $jsonPath", "- Logs: $(Join-Path $RunDirectory 'logs')")
    $lines | Set-Content -LiteralPath $mdPath -Encoding utf8
    return [pscustomobject]@{ Json = $jsonPath; Markdown = $mdPath }
}

Export-ModuleMember -Function *
