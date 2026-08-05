# Local acceptance automation

These scripts reduce the remaining device and private-data acceptance work to explicit local inputs and a small number of device interactions. Evidence is written under `.acceptance/`, which is ignored by Git.

## Safety rules

- Do not copy private photos, Timeline JSON, coordinates, place names, signing files, passwords, or secret values into GitHub issues, pull requests, logs, or the repository.
- Keep only aggregate counts, elapsed time, peak RSS, warning codes, artifact metadata, and PASS/BLOCKER decisions.
- Run one acceptance process at a time. The shared lock prevents concurrent Flutter, Gradle, emulator, and adb acceptance runs from using the same working directories.
- Never remove `.acceptance/.local-acceptance.lock` until all related processes have been checked.

## Interrupted deletion recovery

Prerequisites:

- Windows PowerShell 7
- Flutter and Android platform tools on `PATH`
- a booted emulator or device where `run-as com.kaenozu.kokoitta_app` is permitted

Run:

```powershell
pwsh ./tools/local_acceptance/Invoke-KokoittaDeletionRecoveryAcceptance.ps1 `
  -Serial emulator-5554
```

The script builds and installs the debug APK, starts the app, waits for `pendingDeletionManifestV1`, force-stops the process, restarts it, and verifies manifest/original/trash consistency. The only manual action is creating or selecting a trip with a photo and tapping Delete. Do not tap Undo.

Use `-KeepInstalledData` when an existing local trip should be used. Use `-ApkPath` with `-SkipBuild` to validate an exact APK.

A PASS requires:

- the pending manifest is detected before the interruption;
- after restart no item exists in both original and trash;
- no referenced item is missing from both locations unless it is finalized as deleted;
- physical state and actual file location agree;
- recovery does not leave an operation in `staged`;
- logcat has no matching fatal exception, ANR, OOM, or fatal signal.

## Signed artifact verification

```powershell
pwsh ./tools/release/Verify-AndroidReleaseArtifact.ps1 `
  -ArtifactPath C:\release\app-release.apk `
  -ExpectedApplicationId com.kaenozu.kokoitta_app `
  -ExpectedVersionName 1.0.0 `
  -ExpectedVersionCode 1
```

For an AAB, also pass `-BundletoolJar`. The verifier checks the SHA-256, application ID, version metadata, JAR or APK signature, bundletool validation, and rejects an Android Debug certificate unless `-AllowDebugCertificate` is explicitly supplied.

The script never reads or reports keystore passwords or secret values.

## Combined acceptance

`Invoke-AllLocalAcceptance.ps1` coordinates kokoitta, kurashilog, and privacy_stamp repositories sequentially. It is installed in this repository because it already owns the shared Android acceptance environment. Supply the three repository paths and the two private input paths. The aggregate report contains child report locations and outcomes, not private file paths or contents.
