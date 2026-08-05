[CmdletBinding()]
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
    [string]$Serial = 'emulator-5554',
    [string]$PackageName = 'com.kaenozu.kokoitta_app',
    [string]$ApkPath,
    [int]$ManifestWaitSeconds = 180,
    [int]$RecoveryWaitSeconds = 8,
    [switch]$SkipBuild,
    [switch]$KeepInstalledData,
    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Acceptance.Common.psm1') -Force

$startedAt = (Get-Date).ToString('o')
$runDirectory = New-AcceptanceRun -Name 'kokoitta-deletion-recovery' -Root (Join-Path $RepoRoot '.acceptance')
$lock = $null
$checks = [System.Collections.Generic.List[object]]::new()
$result = 'BLOCKER'

function Add-Check([string]$Name, [string]$Status, [string]$Detail) {
    $checks.Add([ordered]@{ name = $Name; status = $Status; detail = $Detail })
}

try {
    $lock = Enter-AcceptanceLock -Root (Join-Path $RepoRoot '.acceptance')
    Assert-ExternalCommand adb | Out-Null
    Assert-ExternalCommand git | Out-Null
    if (-not $SkipBuild -and [string]::IsNullOrWhiteSpace($ApkPath)) { Assert-ExternalCommand flutter | Out-Null }

    Wait-AndroidBoot -Serial $Serial
    Invoke-Adb -Serial $Serial -Arguments @('logcat', '-c') | Out-Null

    if (-not $SkipBuild -and [string]::IsNullOrWhiteSpace($ApkPath)) {
        Push-Location $RepoRoot
        try {
            Invoke-External -FilePath (Assert-ExternalCommand flutter) -Arguments @('build', 'apk', '--debug') -LogPath (Join-Path $runDirectory 'logs/flutter-build.log') | Out-Null
            $ApkPath = Join-Path $RepoRoot 'build/app/outputs/flutter-apk/app-debug.apk'
        } finally { Pop-Location }
    }
    if ([string]::IsNullOrWhiteSpace($ApkPath)) { throw 'Specify -ApkPath or omit -SkipBuild.' }
    $ApkPath = [System.IO.Path]::GetFullPath($ApkPath)
    if (-not (Test-Path -LiteralPath $ApkPath)) { throw "APK not found: $ApkPath" }

    if (-not $KeepInstalledData) {
        Invoke-Adb -Serial $Serial -Arguments @('uninstall', $PackageName) -AllowFailure -LogPath (Join-Path $runDirectory 'logs/uninstall.log') | Out-Null
    }
    Invoke-Adb -Serial $Serial -Arguments @('install', '-r', '-t', $ApkPath) -LogPath (Join-Path $runDirectory 'logs/install.log') | Out-Null
    Add-Check 'APK install' 'PASS' 'Debug APK installed successfully.'

    Invoke-Adb -Serial $Serial -Arguments @('shell', 'am', 'force-stop', $PackageName) | Out-Null
    Invoke-Adb -Serial $Serial -Arguments @('shell', 'monkey', '-p', $PackageName, '-c', 'android.intent.category.LAUNCHER', '1') -LogPath (Join-Path $runDirectory 'logs/launch-before.log') | Out-Null
    Start-Sleep -Seconds 3

    $beforeSnapshot = Get-AppSandboxSnapshot -Serial $Serial -PackageName $PackageName
    $beforeSnapshot | Set-Content -LiteralPath (Join-Path $runDirectory 'evidence/sandbox-before.txt') -Encoding utf8

    if (-not $NonInteractive) {
        Write-Host ''
        Write-Host 'On the device, create or use a trip with at least one photo, then tap delete.' -ForegroundColor Cyan
        Write-Host 'Do not press Undo. This script will detect the pending manifest and immediately force-stop the app.' -ForegroundColor Cyan
    }

    $deadline = (Get-Date).AddSeconds($ManifestWaitSeconds)
    $manifestXml = $null
    do {
        $manifestXml = Get-PendingDeletionManifestXml -Serial $Serial -PackageName $PackageName
        if ($manifestXml) { break }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    if (-not $manifestXml) { throw "pendingDeletionManifestV1 was not detected within $ManifestWaitSeconds seconds." }

    $interruptedManifest = ConvertFrom-PendingDeletionManifestXml -XmlText $manifestXml
    if (-not $interruptedManifest -or -not $interruptedManifest.operations) { throw 'Pending deletion manifest was present but could not be parsed.' }
    Add-Check 'Pending manifest detection' 'PASS' "Detected $(@($interruptedManifest.operations).Count) operation(s) before process interruption."

    Invoke-Adb -Serial $Serial -Arguments @('shell', 'am', 'force-stop', $PackageName) -LogPath (Join-Path $runDirectory 'logs/force-stop.log') | Out-Null
    Invoke-Adb -Serial $Serial -Arguments @('shell', 'am', 'kill', $PackageName) -AllowFailure | Out-Null
    $interruptedSnapshot = Get-AppSandboxSnapshot -Serial $Serial -PackageName $PackageName
    $interruptedSnapshot | Set-Content -LiteralPath (Join-Path $runDirectory 'evidence/sandbox-interrupted.txt') -Encoding utf8

    Invoke-Adb -Serial $Serial -Arguments @('shell', 'monkey', '-p', $PackageName, '-c', 'android.intent.category.LAUNCHER', '1') -LogPath (Join-Path $runDirectory 'logs/launch-after.log') | Out-Null
    Start-Sleep -Seconds $RecoveryWaitSeconds

    $afterSnapshot = Get-AppSandboxSnapshot -Serial $Serial -PackageName $PackageName
    $afterSnapshot | Set-Content -LiteralPath (Join-Path $runDirectory 'evidence/sandbox-after.txt') -Encoding utf8
    $afterXml = Get-PendingDeletionManifestXml -Serial $Serial -PackageName $PackageName
    $afterManifest = ConvertFrom-PendingDeletionManifestXml -XmlText $afterXml

    $contradictions = [System.Collections.Generic.List[string]]::new()
    $operationsToCheck = if ($afterManifest -and $afterManifest.operations) { @($afterManifest.operations) } else { @($interruptedManifest.operations) }
    foreach ($operation in $operationsToCheck) {
        foreach ($item in @($operation.items)) {
            $originalExists = Test-AppPathExists -Serial $Serial -PackageName $PackageName -Path ([string]$item.originalPath)
            $trashExists = Test-AppPathExists -Serial $Serial -PackageName $PackageName -Path ([string]$item.trashPath)
            if ($originalExists -and $trashExists) {
                $contradictions.Add("Both original and trash exist for photo index $($item.photoIndex).")
            }
            if (-not $originalExists -and -not $trashExists) {
                $state = [string]$item.physicalState
                if ($afterManifest -or $state -ne 'deleted') {
                    $contradictions.Add("Neither original nor trash exists for photo index $($item.photoIndex), state=$state.")
                }
            }
            if ($afterManifest) {
                switch ([string]$item.physicalState) {
                    'staged' { if ($originalExists -or -not $trashExists) { $contradictions.Add("staged item does not exist only in trash for photo index $($item.photoIndex).") } }
                    'restored' { if (-not $originalExists -or $trashExists) { $contradictions.Add("restored item does not exist only in original for photo index $($item.photoIndex).") } }
                    'deleted' { if ($originalExists -or $trashExists) { $contradictions.Add("deleted item still exists for photo index $($item.photoIndex).") } }
                    default { $contradictions.Add("Unknown physicalState '$($item.physicalState)'.") }
                }
            }
        }
    }

    if ($afterManifest -and $afterManifest.operations) {
        $invalidStates = @($afterManifest.operations | Where-Object { [string]$_.state -notin @('pending', 'undoFailed', 'undoCommitFailed', 'undoRollbackFailed', 'cleanupFailed') })
        if ($invalidStates.Count -gt 0) { $contradictions.Add('Recovery left one or more operations in an invalid staged state.') }
    }

    if ($contradictions.Count -eq 0) {
        Add-Check 'Manifest/original/trash consistency' 'PASS' 'No duplicate, missing, or state/path contradiction was found after restart.'
    } else {
        Add-Check 'Manifest/original/trash consistency' 'FAIL' ($contradictions -join ' ')
    }

    $crashes = Get-AppCrashSummary -Serial $Serial -PackageName $PackageName -LogPath (Join-Path $runDirectory 'logs/logcat.txt')
    if ($crashes.Count -eq 0) { Add-Check 'Crash/ANR/OOM logcat' 'PASS' 'No matching fatal event was found.' }
    else { Add-Check 'Crash/ANR/OOM logcat' 'FAIL' ($crashes -join ' | ') }

    $result = if ($contradictions.Count -eq 0 -and $crashes.Count -eq 0) { 'PASS' } else { 'BLOCKER' }
} catch {
    Add-Check 'Execution' 'FAIL' $_.Exception.Message
    $result = 'BLOCKER'
} finally {
    if ($lock) { Exit-AcceptanceLock -Handle $lock -Root (Join-Path $RepoRoot '.acceptance') }
    $head = try { (Invoke-External -FilePath (Assert-ExternalCommand git) -Arguments @('-C', $RepoRoot, 'rev-parse', 'HEAD') -AllowFailure).Lines[0] } catch { 'unknown' }
    $report = [ordered]@{
        name = 'kokoitta interrupted deletion recovery acceptance'
        result = $result
        startedAt = $startedAt
        finishedAt = (Get-Date).ToString('o')
        repositoryHead = $head
        device = $Serial
        packageName = $PackageName
        checks = @($checks)
        privacy = [ordered]@{
            privateFilesCopiedToRepository = $false
            manifestPayloadIncludedInReport = $false
            absolutePhotoPathsIncludedInReport = $false
        }
    }
    $paths = Write-AcceptanceReport -Report $report -RunDirectory $runDirectory
    Write-Host "Result: $result"
    Write-Host "Report: $($paths.Markdown)"
}

if ($result -ne 'PASS') { exit 1 }