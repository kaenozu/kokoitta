from pathlib import Path
import subprocess

main = Path('android/app/src/main/kotlin/com/kaenozu/kokoitta_app/MainActivity.kt')
text = main.read_text(encoding='utf-8')

old = '''        val mimeType = resolver.getType(uri)
        val displayName = resolveDisplayName(resolver, uri)
        val extension = resolveExtension(mimeType, displayName)
            ?: return UriCopyResult(
                errorCode = "unsupported_format",
                reason = "未対応の形式です: ${mimeType ?: "不明"}",
            )
        if (remainingRequestBytes <= 0) {
'''
new = '''        val mimeType = resolver.getType(uri)
        val displayName = resolveDisplayName(resolver, uri)
        if (remainingRequestBytes <= 0) {
'''
if text.count(old) != 1:
    raise SystemExit(f'pre-copy block count={text.count(old)}')
text = text.replace(old, new, 1)

old = 'File.createTempFile("share_${session.requestId}_$index-", ".$extension", cacheDir)'
new = 'File.createTempFile("share_${session.requestId}_$index-", ".part", cacheDir)'
if text.count(old) != 1:
    raise SystemExit(f'temp-file block count={text.count(old)}')
text = text.replace(old, new, 1)

old = '''                StopReason.COMPLETED -> UriCopyResult(
                    file = tempFile,
                    displayName = displayName,
                    mimeType = mimeType,
                )
'''
new = '''                StopReason.COMPLETED -> {
                    val validation = SharedImageFormatValidator.validate(
                        file = tempFile,
                        declaredMimeType = mimeType,
                        displayName = displayName,
                    )
                    val detectedFormat = validation.format
                    if (validation.errorCode != null || detectedFormat == null) {
                        failedTemp(
                            tempFile,
                            validation.errorCode ?: "unsupported_format",
                            validation.reason ?: "未対応または破損した画像です",
                        )
                    } else {
                        val finalized = finalizeTempFile(tempFile, detectedFormat.extension, session)
                        UriCopyResult(
                            file = finalized,
                            displayName = displayName,
                            mimeType = detectedFormat.canonicalMimeType,
                        )
                    }
                }
'''
if text.count(old) != 1:
    raise SystemExit(f'completed block count={text.count(old)}')
text = text.replace(old, new, 1)

marker = '''    private fun failedTemp(file: File, code: String, reason: String): UriCopyResult {
'''
helper = '''    private fun finalizeTempFile(
        temporaryFile: File,
        extension: String,
        session: RequestSession,
    ): File {
        val finalFile = File(
            temporaryFile.parentFile,
            "${temporaryFile.name.substringBeforeLast('.')}.$extension",
        )
        if (!temporaryFile.renameTo(finalFile)) {
            throw IOException("一時画像の形式確定に失敗しました")
        }
        session.tempFiles.remove(temporaryFile)
        session.tempFiles += finalFile
        return finalFile
    }

'''
if text.count(marker) != 1:
    raise SystemExit(f'failedTemp marker count={text.count(marker)}')
text = text.replace(marker, helper + marker, 1)

old = '''    internal fun resolveExtension(mimeType: String?, displayName: String?): String? {
        val mimeToExt = mapOf(
            "image/jpeg" to "jpg",
            "image/png" to "png",
            "image/heic" to "heic",
            "image/heif" to "heic",
            "image/webp" to "webp",
            "image/gif" to "gif",
            "image/bmp" to "bmp",
            "image/x-ms-bmp" to "bmp",
            "image/vnd.wap.wbmp" to "wbmp",
            "image/svg+xml" to "svg",
            "image/tiff" to "tiff",
            "image/x-icon" to "ico",
        )
        val knownImageExtensions = setOf(
            "jpg", "jpeg", "png", "heic", "heif", "webp", "gif",
            "bmp", "wbmp", "svg", "tiff", "tif", "ico",
        )
        val fromMime = mimeType?.lowercase()?.let { mimeToExt[it] }
        if (fromMime != null) return fromMime
        if (mimeType != null && mimeType.startsWith("image/") && displayName != null) {
            val dotIndex = displayName.lastIndexOf('.')
            if (dotIndex >= 0 && dotIndex < displayName.length - 1) {
                val ext = displayName.substring(dotIndex + 1).lowercase()
                if (ext in knownImageExtensions) return ext
            }
        }
        return null
    }
'''
new = '''    internal fun resolveExtension(mimeType: String?, displayName: String?): String? =
        SharedImageFormatValidator.claimedFormat(mimeType, displayName)?.extension
'''
if text.count(old) != 1:
    raise SystemExit(f'resolveExtension block count={text.count(old)}')
text = text.replace(old, new, 1)
main.write_text(text, encoding='utf-8')

staged_path = Path('.github/workflows/agent-47-apply.yml')
staged = staged_path.read_text(encoding='utf-8')
lines = staged.splitlines()
name_index = lines.index('      - name: Apply implementation')
run_index = next(i for i in range(name_index, len(lines)) if lines[i] == '        run: |')
end_index = next(i for i in range(run_index + 1, len(lines)) if lines[i].startswith('      - name: Verify changes'))
shell_lines = [line[10:] if line.startswith('          ') else line for line in lines[run_index + 1:end_index]]
py_start = shell_lines.index("python3 - <<'PY'") + 1
py_end = len(shell_lines) - 1 - shell_lines[::-1].index('PY')
staged_code = '\n'.join(shell_lines[py_start:py_end])
tail_start = staged_code.index("Path('android/app/src/main/kotlin/com/kaenozu/kokoitta_app/SharedImageFormatValidator.kt')")
exec(compile(staged_code[tail_start:], 'agent-47-tail', 'exec'), {'Path': Path, '__name__': '__main__'})

Path('.agent-trigger-47').unlink(missing_ok=True)
Path('.github/workflows/ci.yml').write_bytes(
    subprocess.check_output(['git', 'show', 'origin/main:.github/workflows/ci.yml'])
)
Path(__file__).unlink(missing_ok=True)
