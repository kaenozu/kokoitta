package com.kaenozu.kokoitta_app

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException

private const val SHARE_CHANNEL = "com.kaenozu.kokoitta/share"
private const val MAX_SHARED_IMAGES = 300
private const val MAX_SHARED_BYTES = 700L * 1024L * 1024L
private const val MAX_SINGLE_IMAGE_BYTES = 40L * 1024L * 1024L

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_CHANNEL)
        channel?.setMethodCallHandler { call, result ->
            if (call.method == "getSharedUris") {
                result.success(consumeSharedFiles(intent))
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        channel?.invokeMethod("sharedUris", consumeSharedFiles(intent))
    }

    private fun consumeSharedFiles(source: Intent?): List<String> {
        if (source == null) return emptyList()
        val uris = mutableListOf<Uri>()
        source.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)?.let(uris::add)
        source.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)?.let(uris::addAll)

        source.removeExtra(Intent.EXTRA_STREAM)
        source.action = null

        var remainingBytes = MAX_SHARED_BYTES
        val copiedFiles = mutableListOf<String>()
        for (uri in uris.distinct().take(MAX_SHARED_IMAGES)) {
            val copied = copySharedUri(uri, remainingBytes) ?: continue
            remainingBytes -= copied.length()
            copiedFiles.add(copied.absolutePath)
        }
        return copiedFiles
    }

    private fun copySharedUri(uri: Uri, remainingBytes: Long): File? {
        var target: File? = null
        return runCatching {
            target = File.createTempFile("shared_", ".img", cacheDir)
            val input = contentResolver.openInputStream(uri)
                ?: throw IOException("共有画像を開けません")
            var copiedBytes = 0L
            input.use { source ->
                target!!.outputStream().use { output ->
                    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                    while (true) {
                        val read = source.read(buffer)
                        if (read < 0) break
                        copiedBytes += read
                        if (copiedBytes > MAX_SINGLE_IMAGE_BYTES || copiedBytes > remainingBytes) {
                            throw IOException("共有画像の容量が上限を超えています")
                        }
                        output.write(buffer, 0, read)
                    }
                }
            }
            target!!
        }.getOrElse {
            target?.delete()
            null
        }
    }
}
