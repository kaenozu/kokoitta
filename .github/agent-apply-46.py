from pathlib import Path
import subprocess

release = Path('.github/workflows/release.yml')
text = release.read_text(encoding='utf-8')
marker = '''      - name: Cleanup signing secrets
        if: always()
'''
step = '''      - name: Verify APK and AAB metadata
        env:
          EXPECTED_VERSION: ${{ needs.validate.outputs.version }}
          EXPECTED_VERSION_CODE: ${{ needs.validate.outputs.version_code }}
          EXPECTED_APPLICATION_ID: com.kaenozu.kokoitta_app
        run: |
          scripts/verify-release-artifacts.sh \\
            --apk build/app/outputs/flutter-apk/app-release.apk \\
            --aab build/app/outputs/bundle/release/app-release.aab \\
            --version "$EXPECTED_VERSION" \\
            --version-code "$EXPECTED_VERSION_CODE" \\
            --application-id "$EXPECTED_APPLICATION_ID"

'''
if text.count(marker) != 1:
    raise SystemExit(f'cleanup marker count={text.count(marker)}')
release.write_text(text.replace(marker, step + marker, 1), encoding='utf-8')

ci_text = subprocess.check_output(
    ['git', 'show', 'origin/main:.github/workflows/ci.yml'], text=True
)
needle = '          bash -n scripts/validate-release.sh\n'
if ci_text.count(needle) != 1:
    raise SystemExit(f'validate shell marker count={ci_text.count(needle)}')
ci_text = ci_text.replace(
    needle,
    needle + '          bash -n scripts/verify-release-artifacts.sh\n',
    1,
)
needle = '          bash -n test/validate_release_test.sh\n'
if ci_text.count(needle) != 1:
    raise SystemExit(f'test shell marker count={ci_text.count(needle)}')
ci_text = ci_text.replace(
    needle,
    needle + '          bash -n test/verify_release_artifacts_test.sh\n',
    1,
)
old = '''      - name: Test release validation
        run: bash test/validate_release_test.sh
'''
new = '''      - name: Test release validation
        run: |
          bash test/validate_release_test.sh
          bash test/verify_release_artifacts_test.sh
'''
if ci_text.count(old) != 1:
    raise SystemExit(f'release test step count={ci_text.count(old)}')
Path('.github/workflows/ci.yml').write_text(ci_text.replace(old, new, 1), encoding='utf-8')

staged_path = Path('.github/workflows/agent-46-apply.yml')
staged = staged_path.read_text(encoding='utf-8')
lines = staged.splitlines()
name_index = lines.index('      - name: Apply implementation')
run_index = next(i for i in range(name_index, len(lines)) if lines[i] == '        run: |')
end_index = next(i for i in range(run_index + 1, len(lines)) if lines[i].startswith('      - name: Verify changes'))
shell_lines = [line[10:] if line.startswith('          ') else line for line in lines[run_index + 1:end_index]]
py_start = shell_lines.index("python3 - <<'PY'") + 1
py_end = len(shell_lines) - 1 - shell_lines[::-1].index('PY')
staged_code = '\n'.join(shell_lines[py_start:py_end])
tail_start = staged_code.index("gradle = Path('android/build.gradle.kts')")
exec(compile(staged_code[tail_start:], 'agent-46-tail', 'exec'), {'Path': Path, '__name__': '__main__'})

verifier = Path('scripts/verify-release-artifacts.sh')
verifier_lines = verifier.read_text(encoding='utf-8').splitlines()
changed = 0
for index, line in enumerate(verifier_lines):
    if "tr -d '\\r' | sed" in line:
        indent = line[: len(line) - len(line.lstrip())]
        verifier_lines[index] = (
            indent
            + "tr -d '\\r' | sed -e 's/^[[:space:]]*//' "
            + "-e 's/[[:space:]]*$//' -e 's/^\"//' -e 's/\"$//' | tail -n 1"
        )
        changed += 1
if changed != 1:
    raise SystemExit(f'normalization line count={changed}')
verifier.write_text('\n'.join(verifier_lines) + '\n', encoding='utf-8')

staged_path.unlink(missing_ok=True)
Path('.agent-trigger-46').unlink(missing_ok=True)
Path(__file__).unlink(missing_ok=True)
