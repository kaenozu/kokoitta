package com.kaenozu.kokoitta_app

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.io.IOException

private const val TAG = "KokoittaShareImport"
private const val SHARE_CHANNEL = "com.kaenozu.kokoitta/share"
private const val MAX_SHARED_IMAGES = 300
private const val MAX_SHARED_BYTES = 700L * 1024L * 1024L
private const val MAX_SINGLE_IMAGE_BYTES = 40L * 1024L * 1024L

class MainActivity : FlutterActivity() {
    private data class RequestSession(
        val requestId: String,
        val generation: Long,
        val tempFiles: MutableSet<File> = linkedSetOf(),
        var resultDelivered: Boolean = false,
        var job: Job? = null,
    )

    private var channel: MethodChannel? = null
    private var activeSession: RequestSession? = null
    private val pendingRequests = PendingShareQueue<Intent>()
    private val requestIdGenerator = ShareRequestIdGenerator()
    private val ownership = RequestOwnership()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_CHANNEL)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getSharedUris" -> handleGetSharedUris(result)
                "cancelSharedImport" -> {
                    cancelActiveRequest()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        startRequest(intent)
    }

    override fun onDestroy() {
        // pending中・進行中の共有をすべて破棄する。pendingを先に消すことで
        // cancelActiveRequest内のpending処理起動が空振りする。
        pendingRequests.clear()
        cancelActiveRequest()
        cleanupSession(activeSession)
        activeSession = null
        scope.cancel()
        super.onDestroy()
    }

    private fun handleGetSharedUris(result: MethodChannel.Result) {
        startRequest(intent, result)
    }

    private fun startRequest(source: Intent, initialResult: MethodChannel.Result? = null) {
        if (activeSession != null) {
            // 進行中（コピー中・Flutter処理中を問わず）のsessionがある間は、
            // 新しい共有Intentをcancelせずpendingキューへ積み、現在のsessionが
            // 完全に終了（deliverResultのcallback完了 or job完了）してから順次
            // 処理する。これによりFlutter側は常に現在のrequestのイベントだけを
            // 受信し、busy拒否や旧sessionのtempFiles削除で写真が失われない。
            // 初期method callは即時ackする（結果はimportProgress/importResult
            // で通知されるため、冷間起動と同じ契約）。
            pendingRequests.enqueue(source)
            initialResult?.success(null)
            return
        }
        startSession(source, initialResult)
    }

    private fun startSession(source: Intent, initialResult: MethodChannel.Result? = null) {
        // 共有URIの無いintent（ランチャー起動・テキストのみの共有など）は
        // セッションを開始しない。開始すると「0枚を取り込みました」という
        // completed結果がFlutterに届き、起動のたびに誤表示されるため。
        if (extractUris(source).isEmpty()) {
            consumeIntent(source)
            initialResult?.success(null)
            return
        }
        val requestId = nextRequestId(source)
        val generation = ownership.start(requestId)
        if (generation == null) {
            initialResult?.success(null)
            return
        }
        val session = RequestSession(requestId, generation)
        activeSession = session
        // The initial method call is acknowledged immediately. The actual
        // result is delivered through importProgress/importResult so the same
        // contract is used for cold-start and onNewIntent sharing.
        initialResult?.success(null)
        session.job = scope.launch {
            try {
                processSharedFiles(source, session)
            } catch (error: Throwable) {
                if (error !is kotlinx.coroutines.CancellationException) {
                    Log.e(TAG, "share import failed for ${session.requestId}", error)
                    deliverResult(
                        session,
                        resultMap(
                            session,
                            phase = "failed",
                            processed = maxOf(extractUris(source).size, 1),
                            total = maxOf(extractUris(source).size, 1),
                            successes = emptyList(),
                            failures = listOf(failure(0, "unexpected_error", error.message ?: "取り込みに失敗しました")),
                        ),
                    )
                }
            } finally {
                if (!session.resultDelivered) cleanupSession(session)
                if (ownership.owns(session.requestId, session.generation)) {
                    ownership.finish(session.requestId, session.generation)
                }
            }
        }
    }

    /// 同一URI集合の再共有でも毎回ユニークなrequestIdを発行する。
    ///
    /// [computeRequestId]（内容ベースのMD5）はそのまま残し、単調増加カウンタを
    /// 付加する。Flutter側の終了・キャンセル履歴はrequestId単位で管理される
    /// ため、ユニーク化により再共有がセッション中恒久ブロックされなくなる。
    private fun nextRequestId(source: Intent): String =
        requestIdGenerator.next(computeRequestId(source))

    private fun cancelActiveRequest() {
        val session = activeSession ?: return
        ownership.cancel(session.requestId, session.generation)
        session.job?.cancel()
        cleanupSession(session)
        if (activeSession === session) activeSession = null
        // UIキャンセルは現在のrequestだけを止める。pending済みの共有は続行する。
        processPendingRequests()
    }

    /// 現在のsessionが終了したときだけ呼ぶ。次のpending requestを順次開始する。
    private fun endSession(session: RequestSession) {
        if (activeSession !== session) return
        activeSession = null
        processPendingRequests()
    }

    private fun processPendingRequests() {
        // 1件をstartSessionが開始するとactiveSessionが立つため、次のループで
        // 停止する。startSessionが失敗（generation null）した場合は次へ進む。
        while (activeSession == null) {
            val next = pendingRequests.pollFirst() ?: return
            startSession(next)
        }
    }

    internal fun computeRequestId(intent: Intent): String {
        return ShareIntentContract.computeRequestId(intent)
    }

    internal fun consumeIntent(source: Intent) {
        ShareIntentContract.consumeIntent(source)
    }

    internal fun extractUris(source: Intent): List<Uri> {
        val uris = mutableListOf<Uri>()
        source.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)?.let(uris::add)
        source.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)?.let(uris::addAll)
        return uris.distinct()
    }

    private suspend fun processSharedFiles(source: Intent, session: RequestSession) {
        val uris = extractUris(source)
        if (uris.size > MAX_SHARED_IMAGES) {
            consumeIntent(source)
            deliverResult(
                session,
                resultMap(
                    session,
                    phase = "failed",
                    processed = uris.size,
                    total = uris.size,
                    successes = emptyList(),
                    failures = listOf(failure(0, "count_limit_exceeded", "写真は${MAX_SHARED_IMAGES}枚まで取り込めます")),
                ),
            )
            return
        }

        emitProgress(session, "preparing", 0, uris.size, 0, 0, false)
        val successes = mutableListOf<Map<String, Any>>()
        val failures = mutableListOf<Map<String, Any>>()
        var cumulativeBytes = 0L

        for ((index, uri) in uris.withIndex()) {
            ensureOwner(session)
            emitProgress(session, "copying", index, uris.size, successes.size, failures.size, false)
            val copyResult = withContext(Dispatchers.IO) {
                copyUriToTempFile(uri, index, session, MAX_SHARED_BYTES - cumulativeBytes)
            }
            if (copyResult.errorCode != null) {
                failures += failure(index, copyResult.errorCode, copyResult.reason ?: "コピーに失敗しました")
            } else if (copyResult.file != null) {
                val fileSize = copyResult.file.length()
                cumulativeBytes += fileSize
                successes += mapOf(
                    "path" to copyResult.file.absolutePath,
                    "name" to (copyResult.displayName ?: "image_${index + 1}"),
                    "mimeType" to (copyResult.mimeType ?: "application/octet-stream"),
                    "size" to fileSize,
                )
            }
            emitProgress(session, "copying", index + 1, uris.size, successes.size, failures.size, false)
        }

        consumeIntent(source)
        val phase = when {
            failures.isEmpty() -> "completed"
            successes.isEmpty() -> "failed"
            else -> "partialFailure"
        }
        deliverResult(
            session,
            resultMap(session, phase, uris.size, uris.size, successes, failures),
        )
    }

    private fun ensureOwner(session: RequestSession) {
        if (!coroutineContextIsActive() || !ownership.owns(session.requestId, session.generation)) {
            throw kotlinx.coroutines.CancellationException("share request is no longer active")
        }
    }

    private fun coroutineContextIsActive(): Boolean =
        activeSession?.let { it.job?.isActive == true } == true && !isFinishing

    private fun emitProgress(
        session: RequestSession,
        phase: String,
        processed: Int,
        total: Int,
        succeeded: Int,
        failed: Int,
        terminal: Boolean,
    ) {
        if (!ownership.owns(session.requestId, session.generation)) return
        channel?.invokeMethod(
            "importProgress",
            mapOf(
                "requestId" to session.requestId,
                "phase" to phase,
                "processed" to processed,
                "total" to total,
                "succeeded" to succeeded,
                "failed" to failed,
                "terminal" to terminal,
            ),
        )
    }

    private fun deliverResult(session: RequestSession, payload: Map<String, Any>) {
        if (!ownership.owns(session.requestId, session.generation)) {
            cleanupSession(session)
            endSession(session)
            return
        }
        val currentChannel = channel
        if (currentChannel == null) {
            cleanupSession(session)
            endSession(session)
            return
        }
        session.resultDelivered = true
        currentChannel.invokeMethod("importResult", payload, object : MethodChannel.Result {
            override fun success(result: Any?) {
                val successPaths = (payload["successes"] as? List<*>)
                    ?.mapNotNull { (it as? Map<*, *>)?.get("path") as? String }
                    ?.toSet()
                    ?: emptySet()
                cleanupSession(session, keepPaths = successPaths)
                ownership.finish(session.requestId, session.generation)
                endSession(session)
            }

            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                Log.e(TAG, "Flutter rejected import result: $errorCode $errorMessage")
                cleanupSession(session)
                ownership.finish(session.requestId, session.generation)
                endSession(session)
            }

            override fun notImplemented() {
                Log.e(TAG, "Flutter does not implement importResult")
                cleanupSession(session)
                ownership.finish(session.requestId, session.generation)
                endSession(session)
            }
        })
    }

    private data class UriCopyResult(
        val file: File? = null,
        val displayName: String? = null,
        val mimeType: String? = null,
        val errorCode: String? = null,
        val reason: String? = null,
    )

    private fun copyUriToTempFile(
        uri: Uri,
        index: Int,
        session: RequestSession,
        remainingRequestBytes: Long,
    ): UriCopyResult {
        val resolver = contentResolver ?: return UriCopyResult(
            errorCode = "cannot_open", reason = "ContentResolverを取得できませんでした",
        )
        val mimeType = resolver.getType(uri)
        val displayName = resolveDisplayName(resolver, uri)
        if (remainingRequestBytes <= 0) {
            return UriCopyResult(errorCode = "total_size_exceeded", reason = "合計容量の上限（700MB）を超えています")
        }

        val tempFile = try {
            File.createTempFile("share_${session.requestId}_$index-", ".part", cacheDir)
                .also { session.tempFiles += it }
        } catch (error: IOException) {
            return UriCopyResult(errorCode = "copy_failed", reason = "一時ファイル作成失敗: ${error.message}")
        }

        return try {
            val inputStream = resolver.openInputStream(uri)
                ?: return failedTemp(tempFile, "cannot_open", "URIを開けませんでした")
            val outcome = inputStream.use { input ->
                FileOutputStream(tempFile).use { output ->
                    BoundedStreamCopier.copy(
                        input,
                        output,
                        minOf(MAX_SINGLE_IMAGE_BYTES, remainingRequestBytes),
                        isCancelled = {
                            !coroutineContextIsActive() ||
                                !ownership.owns(session.requestId, session.generation)
                        },
                    )
                }
            }
            when (outcome.stopped) {
                StopReason.CANCELLED -> failedTemp(tempFile, "cancelled", "取り込みがキャンセルされました")
                StopReason.LIMIT_EXCEEDED -> {
                    val code = if (outcome.bytesCopied >= MAX_SINGLE_IMAGE_BYTES) {
                        "single_size_exceeded"
                    } else {
                        "total_size_exceeded"
                    }
                    failedTemp(tempFile, code, "サイズ上限を超えたため取り込みを中断しました")
                }
                StopReason.COMPLETED -> {
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
            }
        } catch (error: SecurityException) {
            failedTemp(tempFile, "cannot_open", "ストレージアクセスが拒否されました")
        } catch (error: IOException) {
            failedTemp(tempFile, "copy_failed", "コピー失敗: ${error.message}")
        } catch (error: OutOfMemoryError) {
            failedTemp(tempFile, "copy_failed", "ファイルサイズが大きすぎて処理できません")
        }
    }

    private fun finalizeTempFile(
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

    private fun failedTemp(file: File, code: String, reason: String): UriCopyResult {
        deleteTrackedFile(file)
        return UriCopyResult(errorCode = code, reason = reason)
    }

    private fun cleanupSession(session: RequestSession?, keepPaths: Set<String> = emptySet()) {
        session ?: return
        val files = session.tempFiles.toList()
        for (file in files) {
            if (file.absolutePath in keepPaths) {
                session.tempFiles.remove(file)
            } else {
                deleteTrackedFile(file)
            }
        }
    }

    private fun deleteTrackedFile(file: File) {
        activeSession?.tempFiles?.remove(file)
        try {
            if (file.exists() && !file.delete()) {
                Log.e(TAG, "temporary import cleanup failed: ${file.absolutePath}")
            }
        } catch (error: SecurityException) {
            Log.e(TAG, "temporary import cleanup failed: ${file.absolutePath}", error)
        }
    }

    private fun resultMap(
        session: RequestSession,
        phase: String,
        processed: Int,
        total: Int,
        successes: List<Map<String, Any>>,
        failures: List<Map<String, Any>>,
    ): Map<String, Any> = mapOf(
        "requestId" to session.requestId,
        "phase" to phase,
        "processed" to processed,
        "total" to total,
        "succeeded" to successes.size,
        "failed" to failures.size,
        "terminal" to true,
        "successes" to successes,
        "failures" to failures,
    )

    private fun failure(index: Int, errorCode: String, reason: String): Map<String, Any> = mapOf(
        "index" to index,
        "errorCode" to errorCode,
        "reason" to reason,
    )

    internal fun resolveExtension(mimeType: String?, displayName: String?): String? =
        SharedImageFormatValidator.claimedFormat(mimeType, displayName)?.extension

    private fun resolveDisplayName(resolver: android.content.ContentResolver, uri: Uri): String? = try {
        resolver.query(uri, null, null, null, null)?.use {
            if (it.moveToFirst()) {
                val nameIndex = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (nameIndex >= 0) it.getString(nameIndex) else null
            } else null
        }
    } catch (error: Exception) {
        Log.w(TAG, "could not read display name", error)
        null
    }
}
