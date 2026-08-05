[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$AabPath,
    [Parameter(Mandatory)][string]$ExpectedApplicationId,
    [Parameter(Mandatory)][string]$ExpectedVersionName,
    [Parameter(Mandatory)][string]$ExpectedVersionCode,
    [Parameter(Mandatory)][string]$BundletoolJar,
    [Parameter(Mandatory)][string]$ReleaseNotesPath,
    [string]$OutputRoot = '.acceptance/play-console-handoff'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$verifier = Join-Path $scriptDirectory 'Verify-AndroidReleaseArtifact.ps1'
if (-not (Test-Path -LiteralPath $verifier)) { throw "Artifact verifier not found: $verifier" }
$aab = [System.IO.Path]::GetFullPath($AabPath)
$notesPath = [System.IO.Path]::GetFullPath($ReleaseNotesPath)
if (-not (Test-Path -LiteralPath $notesPath -PathType Leaf)) { throw 'Release notes file not found.' }
$notes = (Get-Content -LiteralPath $notesPath -Raw).Trim()
if ([string]::IsNullOrWhiteSpace($notes)) { throw 'Release notes must not be empty.' }
if ($notes -match '(?i)TODO|TBD|PLACEHOLDER') { throw 'Release notes contain an unresolved placeholder.' }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$output = [System.IO.Path]::GetFullPath((Join-Path $OutputRoot $stamp))
New-Item -ItemType Directory -Path $output -Force | Out-Null
& $verifier `
    -ArtifactPath $aab `
    -ExpectedApplicationId $ExpectedApplicationId `
    -ExpectedVersionName $ExpectedVersionName `
    -ExpectedVersionCode $ExpectedVersionCode `
    -BundletoolJar $BundletoolJar `
    -ReportDirectory $output
if ($LASTEXITCODE -ne 0) { throw 'AAB verification failed; Play Console handoff was not created.' }

$artifactReportPath = Join-Path $output 'android-artifact-report.json'
$artifactReport = Get-Content -LiteralPath $artifactReportPath -Raw | ConvertFrom-Json -Depth 30
if ($artifactReport.result -ne 'PASS') { throw 'Artifact report is not PASS.' }
Copy-Item -LiteralPath $notesPath -Destination (Join-Path $output 'release-notes.txt')
$handoff = [ordered]@{
    result = 'READY_FOR_PRIVILEGED_UPLOAD'
    generatedAt = (Get-Date).ToString('o')
    applicationId = $ExpectedApplicationId
    versionName = $ExpectedVersionName
    versionCode = $ExpectedVersionCode
    artifactFileName = [System.IO.Path]::GetFileName($aab)
    artifactSha256 = $artifactReport.artifact.sha256
    artifactVerificationReport = $artifactReportPath
    releaseNotesFile = (Join-Path $output 'release-notes.txt')
    secretValuesIncluded = $false
    remainingActions = @(
        'Confirm the target Play Console application matches applicationId.',
        'Confirm this versionCode has never been uploaded.',
        'Choose the intended track and rollout percentage.',
        'Upload the exact verified AAB.',
        'Paste the included release notes.',
        'Review automated device-test results and policy warnings.',
        'Start rollout only after final human approval.'
    )
}
$handoff | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $output 'play-console-handoff.json') -Encoding utf8
@(
    '# Play Console handoff', '',
    '- Result: **READY_FOR_PRIVILEGED_UPLOAD**',
    "- Application ID: $ExpectedApplicationId",
    "- Version: $ExpectedVersionName ($ExpectedVersionCode)",
    "- AAB SHA-256: $($artifactReport.artifact.sha256)",
    '- Secret values: not included',
    '',
    '## Remaining privileged actions'
) + @($handoff.remainingActions | ForEach-Object { "- $_" }) | Set-Content -LiteralPath (Join-Path $output 'play-console-handoff.md') -Encoding utf8
Write-Host 'Result: READY_FOR_PRIVILEGED_UPLOAD'
Write-Host "Handoff: $(Join-Path $output 'play-console-handoff.md')"
