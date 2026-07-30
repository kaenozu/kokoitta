package com.kaenozu.kokoitta_app

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.coroutines.coroutineContext
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.security.MessageDigest

private const val SHARE_CHANNEL = "com.kaenozu.kokoitta/share"
private const val MAX_SHARED_IMAGES = 300
private const val MAX_SHARED_BYTES = 700L * 1024L * 1024L
private const val MAX_SINGLE_IMAGE_BYTES = 40L * 1024L * 1024L

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var activeProcessJob: Job? = null
    private var activeRequestId: String? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_CHANNEL)
        channel?.setMethodCallHandler { call, result ->
            if (call.method == "getSharedUris") {
                handleGetSharedUris(call, result)
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val requestId = computeRequestId(intent)
        if (requestId == activeRequestId) return
        activeRequestId = requestId
        activeProcessJob?.cancel()
        activeProcessJob = scope.launch {
            val resultMap = processSharedFiles(intent)
            activeRequestId = null
            channel?.invokeMethod("sharedUris", resultMap)
        }
    }

    override fun onDestroy() {
        activeProcessJob?.cancel()
        scope.cancel()
        super.onDestroy()
    }

    private fun handleGetSharedUris(call: MethodCall, result: MethodChannel.Result) {
        val intent = intent
        val requestId = computeRequestId(intent)
        if (requestId == activeRequestId) {
            result.success(emptyMap<String, Any>())
            return
        }
        activeRequestId = requestId
        activeProcessJob?.cancel()
        activeProcessJob = scope.launch {
            val resultMap = processSharedFiles(intent)
            activeRequestId = null
            result.success(resultMap)
        }
    }

    internal fun computeRequestId(intent: Intent): String {
        val singleUri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
        val multiUris = intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
        val allUris = (listOfNotNull(singleUri) + (multiUris ?: emptyList())).distinct().sorted()
        if (allUris.isEmpty()) return "empty_${intent.action}"
        val joined = allUris.joinToString("|") { it.toString().lowercase() }
        val digest = MessageDigest.getInstance("MD5").digest(joined.toByteArray())
        return digest.joinToString("") { "%02x".format(it) } + "_${intent.action}"
    }

    internal fun consumeIntent(source: Intent) {
        source.removeExtra(Intent.EXTRA_STREAM)
        source.action = null
    }

    internal fun extractUris(source: Intent): List<Uri> {
        val uris = mutableListOf<Uri>()
        source.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)?.let(uris::add)
        source.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)?.let(uris::addAll)
        return uris.distinct()
    }

    private suspend fun processSharedFiles(source: Intent): Map<String, Any> {
        val uris = extractUris(source)
        val receivedCount = uris.size
        val requestId = computeRequestId(source)

        if (receivedCount > MAX_SHARED_IMAGES) {
            consumeIntent(source)
            return mapOf<String, Any>(
                "requestId" to requestId,
                "receivedCount" to receivedCount,
                "acceptedCount" to 0,
                "successes" to emptyList<Map<String, Any>>(),
                "overLimitCount" to (receivedCount - MAX_SHARED_IMAGES),
                "failures" to emptyList<Map<String, Any>>(),
            )
        }

        val successes = mutableListOf<Map<String, Any>>()
        val failures = mutableListOf<Map<String, Any>>()
        var cumulativeBytes = 0L
        val incompleteTempFiles = mutableListOf<File>()

        try {
            for ((index, uri) in uris.withIndex()) {
                if (!coroutineContext.isActive) break

                val copyResult = withContext(Dispatchers.IO) {
                    copyUriToTempFile(uri, index)
                }

                when {
                    copyResult.errorCode != null -> {
                        failures.add(mapOf<String, Any>(
                            "index" to index,
                            "errorCode" to (copyResult.errorCode ?: "unknown"),
                            "reason" to (copyResult.reason ?: ""),
                        ))
                    }
                    copyResult.file != null -> {
                        val fileSize = copyResult.file.length()

                        if (fileSize > MAX_SINGLE_IMAGE_BYTES) {
                            copyResult.file.delete()
                            failures.add(mapOf<String, Any>(
                                "index" to index,
                                "errorCode" to "single_size_exceeded",
                                "reason" to "1枚あたりの上限（40MB）を超えています",
                            ))
                            continue
                        }

                        if (cumulativeBytes + fileSize > MAX_SHARED_BYTES) {
                            copyResult.file.delete()
                            failures.add(mapOf<String, Any>(
                                "index" to index,
                                "errorCode" to "total_size_exceeded",
                                "reason" to "合計容量の上限（700MB）を超えています",
                            ))
                            continue
                        }

                        cumulativeBytes += fileSize
                        successes.add(mapOf<String, Any>(
                            "path" to copyResult.file.absolutePath,
                            "name" to (copyResult.displayName ?: "image_${index + 1}"),
                            "mimeType" to (copyResult.mimeType ?: "application/octet-stream"),
                            "size" to fileSize,
                        ))
                    }
                }
            }
        } finally {
            for (file in incompleteTempFiles) {
                try { file.delete() } catch (_: Exception) {}
            }
        }

        consumeIntent(source)

        return mapOf<String, Any>(
            "requestId" to requestId,
            "receivedCount" to receivedCount,
            "acceptedCount" to successes.size,
            "successes" to successes,
            "overLimitCount" to 0,
            "failures" to failures,
        )
    }

    private data class UriCopyResult(
        val file: File? = null,
        val displayName: String? = null,
        val mimeType: String? = null,
        val errorCode: String? = null,
        val reason: String? = null,
    )

    private fun copyUriToTempFile(uri: Uri, index: Int): UriCopyResult {
        val resolver = contentResolver ?: return UriCopyResult(
            errorCode = "cannot_open", reason = "ContentResolverを取得できませんでした",
        )

        val mimeType = resolver.getType(uri)
        val displayName = resolveDisplayName(resolver, uri)
        val extension = resolveExtension(mimeType, displayName)

        if (extension == null) {
            return UriCopyResult(
                errorCode = "unsupported_format",
                reason = "未対応の形式です: ${mimeType ?: "不明"}",
            )
        }

        val tempFile = try {
            File.createTempFile("share_${index}_", ".$extension", cacheDir)
        } catch (e: IOException) {
            return UriCopyResult(
                errorCode = "copy_failed", reason = "一時ファイル作成失敗: ${e.message}",
            )
        }

        return try {
            val inputStream = resolver.openInputStream(uri)
            if (inputStream == null) {
                tempFile.delete()
                return UriCopyResult(
                    errorCode = "cannot_open", reason = "URIを開けませんでした",
                )
            }
            inputStream.use { input ->
                FileOutputStream(tempFile).use { output ->
                    input.copyTo(output)
                }
            }
            UriCopyResult(file = tempFile, displayName = displayName, mimeType = mimeType)
        } catch (e: SecurityException) {
            tempFile.delete()
            UriCopyResult(errorCode = "cannot_open", reason = "ストレージアクセスが拒否されました")
        } catch (e: IOException) {
            tempFile.delete()
            UriCopyResult(errorCode = "copy_failed", reason = "コピー失敗: ${e.message}")
        } catch (e: OutOfMemoryError) {
            tempFile.delete()
            UriCopyResult(errorCode = "copy_failed", reason = "ファイルサイズが大きすぎて処理できません")
        }
    }

    private fun resolveDisplayName(resolver: android.content.ContentResolver, uri: Uri): String? {
        return try {
            val cursor = resolver.query(uri, null, null, null, null)
            cursor?.use {
                if (it.moveToFirst()) {
                    val nameIndex = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (nameIndex >= 0) it.getString(nameIndex) else null
                } else null
            }
        } catch (_: Exception) {
            null
        }
    }

    internal fun resolveExtension(mimeType: String?, displayName: String?): String? {
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

        if (mimeType != null && mimeType.startsWith("image/")) {
            if (displayName != null) {
                val dotIndex = displayName.lastIndexOf('.')
                if (dotIndex >= 0 && dotIndex < displayName.length - 1) {
                    val ext = displayName.substring(dotIndex + 1).lowercase()
                    if (ext in knownImageExtensions) return ext
                }
            }
        }

        return null
    }
}
