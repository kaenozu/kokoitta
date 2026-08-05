[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$KokoittaRepo,
    [Parameter(Mandatory)][string]$KurashilogRepo,
    [Parameter(Mandatory)][string]$PrivacyStampRepo,
    [string]$TimelineJson,
    [string]$HighResolutionImage,
    [string]$KokoittaSerial = 'emulator-5554',
    [string]$PrivacyStampSerial = 'emulator-5556',
    [int]$PrivacyStampRamMb = 1536,
    [switch]$SkipKokoitta,
    [switch]$SkipKurashilog,
    [switch]$SkipPrivacyStamp,
    [switch]$AllowExistingFlutterProcesses,
    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function FullPath([string]$Path) { [System.IO.Path]::GetFullPath($Path) }
function Redact([string]$Text, [string[]]$PrivateValues) {
    $safe = $Text
    foreach ($value in $PrivateValues) {
        if (-not [string]::IsNullOrWhiteSpace($value)) { $safe = $safe.Replace($value, '<PRIVATE_INPUT_PATH>') }
    }
    $safe
}
function Run-Child([string]$Name, [string]$Script, [string[]]$Arguments, [string]$Log, [string[]]$PrivateValues) {
    $output = @(& pwsh -NoProfile -File $Script @Arguments 2>&1 | ForEach-Object { "$_" })
    $exitCode = $LASTEXITCODE
    $safe = $output | ForEach-Object { Redact $_ $PrivateValues }
    $safe | Set-Content -LiteralPath $Log -Encoding utf8
    [ordered]@{
        name = $Name
        result = $(if ($exitCode -eq 0) { 'PASS' } else { 'BLOCKER' })
        exitCode = $exitCode
        log = $Log
        reportHint = @($safe | Where-Object { $_ -match '^Report:' } | Select-Object -Last 1)
    }
}

$kokoitta = FullPath $KokoittaRepo
$kurashilog = FullPath $KurashilogRepo
$privacyStamp = FullPath $PrivacyStampRepo
foreach ($repo in @($kokoitta, $kurashilog, $privacyStamp)) {
    if (-not (Test-Path -LiteralPath $repo -PathType Container)) { throw "Repository directory not found: $repo" }
}
$timeline = if ($TimelineJson) { FullPath $TimelineJson } else { '' }
$image = if ($HighResolutionImage) { FullPath $HighResolutionImage } else { '' }
if (-not $SkipKurashilog -and -not $timeline) { throw 'Specify -TimelineJson or -SkipKurashilog.' }
if (-not $SkipPrivacyStamp -and -not $image) { throw 'Specify -HighResolutionImage or -SkipPrivacyStamp.' }

$existing = @(Get-Process flutter,dart -ErrorAction SilentlyContinue)
if ($existing.Count -gt 0 -and -not $AllowExistingFlutterProcesses) {
    $details = $existing | ForEach-Object { "$($_.ProcessName):$($_.Id)" }
    throw "Existing Flutter/Dart processes may share caches with acceptance: $($details -join ', '). Stop them or pass -AllowExistingFlutterProcesses after verifying ownership."
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$runDirectory = Join-Path $kokoitta ".acceptance/all-local-acceptance-$stamp"
New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null
$lockPath = Join-Path $kokoitta '.acceptance/.orchestrator.lock'
$lock = $null
$children = [System.Collections.Generic.List[object]]::new()

try {
    try { $lock = [System.IO.File]::Open($lockPath, 'CreateNew', 'ReadWrite', 'None') }
    catch { throw "Another aggregate acceptance run appears active: $lockPath" }

    if (-not $SkipKokoitta) {
        $script = Join-Path $kokoitta 'tools/local_acceptance/Invoke-KokoittaDeletionRecoveryAcceptance.ps1'
        if (-not (Test-Path $script)) { throw "Missing script: $script" }
        $args = @('-RepoRoot', $kokoitta, '-Serial', $KokoittaSerial)
        if ($NonInteractive) { $args += '-NonInteractive' }
        $children.Add((Run-Child 'kokoitta deletion recovery' $script $args (Join-Path $runDirectory 'kokoitta.log') @()))
    }

    if (-not $SkipKurashilog) {
        $script = Join-Path $kurashilog 'tools/local_acceptance/Invoke-KurashilogPrivateTimelineAcceptance.ps1'
        if (-not (Test-Path $script)) { throw "Missing script: $script" }
        $args = @('-RepoRoot', $kurashilog, '-TimelineJson', $timeline)
        $children.Add((Run-Child 'kurashilog private Timeline' $script $args (Join-Path $runDirectory 'kurashilog.log') @($timeline)))
    }

    if (-not $SkipPrivacyStamp) {
        $script = Join-Path $privacyStamp 'tools/local_acceptance/Invoke-PrivacyStampHighResolutionAcceptance.ps1'
        if (-not (Test-Path $script)) { throw "Missing script: $script" }
        $args = @('-RepoRoot', $privacyStamp, '-InputImage', $image, '-Serial', $PrivacyStampSerial, '-RamMb', "$PrivacyStampRamMb")
        if ($NonInteractive) { $args += '-NonInteractive' }
        $children.Add((Run-Child 'privacy_stamp high resolution' $script $args (Join-Path $runDirectory 'privacy_stamp.log') @($image)))
    }

    $blockers = @($children | Where-Object { $_.result -ne 'PASS' })
    $result = if ($blockers.Count -eq 0) { 'PASS' } else { 'BLOCKER' }
    $report = [ordered]@{
        result = $result
        generatedAt = (Get-Date).ToString('o')
        children = @($children)
        privacy = [ordered]@{
            privateInputPathsIncluded = $false
            privateInputContentsCopied = $false
            sharedExecutionWasSequential = $true
        }
    }
    $report | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $runDirectory 'report.json') -Encoding utf8
    $lines = @('# Aggregate local acceptance', '', "- Result: **$result**", '', '## Child runs')
    $lines += @($children | ForEach-Object { "- [$($_.result)] $($_.name) — exit $($_.exitCode); log $($_.log)" })
    $lines += @('', 'Private file paths and source contents are not included in the aggregate report.')
    $lines | Set-Content -LiteralPath (Join-Path $runDirectory 'report.md') -Encoding utf8
    Write-Host "Result: $result"
    Write-Host "Report: $(Join-Path $runDirectory 'report.md')"
    if ($result -ne 'PASS') { exit 1 }
} finally {
    if ($lock) { $lock.Dispose() }
    Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
}
