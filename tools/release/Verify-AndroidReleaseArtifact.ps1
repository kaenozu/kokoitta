[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ArtifactPath,
    [Parameter(Mandatory)][string]$ExpectedApplicationId,
    [string]$ExpectedVersionName,
    [string]$ExpectedVersionCode,
    [string]$BundletoolJar,
    [switch]$AllowDebugCertificate,
    [string]$ReportDirectory = '.acceptance/release-artifact'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$artifact = [System.IO.Path]::GetFullPath($ArtifactPath)
if (-not (Test-Path -LiteralPath $artifact)) { throw "Artifact not found: $artifact" }
$extension = [System.IO.Path]::GetExtension($artifact).ToLowerInvariant()
if ($extension -notin @('.apk', '.aab')) { throw 'Artifact must be .apk or .aab.' }

New-Item -ItemType Directory -Path $ReportDirectory -Force | Out-Null
$reportPath = Join-Path ([System.IO.Path]::GetFullPath($ReportDirectory)) 'android-artifact-report.json'
$checks = [System.Collections.Generic.List[object]]::new()
function Add-Check([string]$Name, [bool]$Passed, [string]$Detail) {
    $checks.Add([ordered]@{ name = $Name; status = $(if ($Passed) { 'PASS' } else { 'FAIL' }); detail = $Detail })
    if (-not $Passed) { $script:hasFailure = $true }
}
function Require-Command([string]$Name) {
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $command) { throw "Required command not found: $Name" }
    $command.Source
}
function Run([string]$File, [string[]]$Args) {
    $output = @(& $File @Args 2>&1 | ForEach-Object { "$_" })
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Text = ($output -join "`n") }
}

$hasFailure = $false
$sha256 = (Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash
$metadata = [ordered]@{ path = $artifact; sha256 = $sha256; type = $extension.TrimStart('.') }

if ($extension -eq '.apk') {
    $apkanalyzer = Require-Command 'apkanalyzer'
    $apksigner = Require-Command 'apksigner'
    $appId = (Run $apkanalyzer @('manifest', 'application-id', $artifact)).Text.Trim()
    $versionName = (Run $apkanalyzer @('manifest', 'version-name', $artifact)).Text.Trim()
    $versionCode = (Run $apkanalyzer @('manifest', 'version-code', $artifact)).Text.Trim()
    $metadata.applicationId = $appId
    $metadata.versionName = $versionName
    $metadata.versionCode = $versionCode
    Add-Check 'applicationId' ($appId -eq $ExpectedApplicationId) "actual=$appId expected=$ExpectedApplicationId"
    if ($ExpectedVersionName) { Add-Check 'versionName' ($versionName -eq $ExpectedVersionName) "actual=$versionName expected=$ExpectedVersionName" }
    if ($ExpectedVersionCode) { Add-Check 'versionCode' ($versionCode -eq $ExpectedVersionCode) "actual=$versionCode expected=$ExpectedVersionCode" }

    $signature = Run $apksigner @('verify', '--verbose', '--print-certs', $artifact)
    Add-Check 'APK signature verification' ($signature.ExitCode -eq 0) 'apksigner verify completed.'
    $debugCertificate = $signature.Text -match 'Android Debug|CN=Android Debug'
    Add-Check 'Production certificate' ($AllowDebugCertificate -or -not $debugCertificate) $(if ($debugCertificate) { 'Debug certificate detected.' } else { 'No Android Debug certificate marker detected.' })
    $metadata.certificateSha256 = ([regex]::Match($signature.Text, 'SHA-256 digest:\s*(?<value>[0-9A-Fa-f:]+)')).Groups['value'].Value
} else {
    $jarsigner = Require-Command 'jarsigner'
    $jarResult = Run $jarsigner @('-verify', '-strict', '-certs', $artifact)
    Add-Check 'AAB JAR signature verification' ($jarResult.ExitCode -eq 0) 'jarsigner -verify -strict completed.'
    if ([string]::IsNullOrWhiteSpace($BundletoolJar)) { throw 'Specify -BundletoolJar for AAB metadata verification.' }
    $java = Require-Command 'java'
    $BundletoolJar = [System.IO.Path]::GetFullPath($BundletoolJar)
    if (-not (Test-Path -LiteralPath $BundletoolJar)) { throw "bundletool jar not found: $BundletoolJar" }
    $validate = Run $java @('-jar', $BundletoolJar, 'validate', '--bundle', $artifact)
    Add-Check 'Bundletool validation' ($validate.ExitCode -eq 0) 'bundletool validate completed.'
    $manifest = Run $java @('-jar', $BundletoolJar, 'dump', 'manifest', '--bundle', $artifact, '--module', 'base')
    if ($manifest.ExitCode -ne 0) { throw 'bundletool dump manifest failed.' }
    $appIdMatch = [regex]::Match($manifest.Text, 'package="(?<value>[^"]+)"')
    $versionNameMatch = [regex]::Match($manifest.Text, 'versionName="(?<value>[^"]+)"')
    $versionCodeMatch = [regex]::Match($manifest.Text, 'versionCode="(?<value>\d+)"')
    $appId = $appIdMatch.Groups['value'].Value
    $versionName = $versionNameMatch.Groups['value'].Value
    $versionCode = $versionCodeMatch.Groups['value'].Value
    $metadata.applicationId = $appId
    $metadata.versionName = $versionName
    $metadata.versionCode = $versionCode
    Add-Check 'applicationId' ($appId -eq $ExpectedApplicationId) "actual=$appId expected=$ExpectedApplicationId"
    if ($ExpectedVersionName) { Add-Check 'versionName' ($versionName -eq $ExpectedVersionName) "actual=$versionName expected=$ExpectedVersionName" }
    if ($ExpectedVersionCode) { Add-Check 'versionCode' ($versionCode -eq $ExpectedVersionCode) "actual=$versionCode expected=$ExpectedVersionCode" }
}

$report = [ordered]@{
    result = $(if ($hasFailure) { 'BLOCKER' } else { 'PASS' })
    generatedAt = (Get-Date).ToString('o')
    artifact = $metadata
    checks = @($checks)
    secretsIncluded = $false
}
$report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $reportPath -Encoding utf8
Write-Host "Result: $($report.result)"
Write-Host "Report: $reportPath"
if ($hasFailure) { exit 1 }