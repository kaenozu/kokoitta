# Issue #90 human acceptance checklist

This checklist separates repeatable repository/device automation from acceptance
that requires a real device, private input, or owner-controlled release access.
An unchecked item is **BLOCKER / NOT VERIFIED**; it must not be reported as
PASS based on widget tests, a debug APK, or a substitute fixture.

## Automated evidence

Run these checks from the Issue #90 worktree. Record the exact HEAD and the
command output in the task report; do not copy private paths or image metadata.

| Gate | Evidence | Status rule |
| --- | --- | --- |
| UI state matrix | `flutter test test/ui_final_qa_matrix_test.dart` | PASS only when the test completes with zero failures and zero skips |
| Flutter regression | `flutter analyze` and `flutter test` | PASS only when both commands complete successfully |
| Android unit tests | `android\\gradlew.bat -p android :app:testDebugUnitTest --no-daemon` | PASS only when the test task completes successfully |
| Debug build | `flutter build apk --debug` | Build evidence only; it does not satisfy signing or Play acceptance |
| Local acceptance script syntax | `.github/workflows/local-acceptance-scripts.yml` validation | PASS only when every PowerShell file parses |
| Interrupted deletion runner | `Invoke-KokoittaDeletionRecoveryAcceptance.ps1` | PASS only with a newly created operation and real device evidence |

## Human-only acceptance

The following gates remain separate from automated checks and are **BLOCKER /
NOT VERIFIED** until the required owner-controlled input and device evidence are
available:

- real Android device or the specified low-memory AVD;
- private real image, including the 48MP/OOM case, with aggregate memory and
  crash/ANR evidence only;
- OEM DocumentsUI import and Google Photos share/import paths;
- TalkBack completion of the primary flows and focus/reading order;
- all required viewport/theme/text-scale checks on a visible device;
- formal release signing certificate and owner-controlled signing secrets;
- Play Console internal-test upload, install, and policy/device warnings.

## Safe execution boundary

The local runner may build/install a debug APK and inspect app-private state only
when the target device and shared acceptance lock are available. It must not
delete user data, copy private inputs into the repository, create or print
signing material, change Play settings, or alter Production state. If a device,
private input, signing secret, or Play permission is unavailable, stop that gate
as `BLOCKER` and retain `KEEP_DRAFT`.

## Completion record

| Category | Result | Evidence / blocker |
| --- | --- | --- |
| Automated repository checks | NOT VERIFIED | Fill with command counts and exact HEAD |
| Visible device UI matrix | BLOCKER | Requires human/device interaction |
| OEM DocumentsUI / Google Photos | BLOCKER | Requires real provider path |
| 48MP / low-memory behavior | BLOCKER | Requires approved private input and device |
| Formal signing / Play internal test | BLOCKER | Requires owner-controlled secrets and Play access |
