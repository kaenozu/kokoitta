package com.kaenozu.kokoitta_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import java.io.File

private const val SHARE_CHANNEL = "com.kaenozu.kokoitta/share"

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_CHANNEL)
        channel?.setMethodCallHandler { call, result ->
            if (call.method == "getSharedUris") {
                result.success(sharedUris(intent))
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        channel?.invokeMethod("sharedUris", sharedUris(intent))
    }

    private fun sharedUris(source: Intent?): List<String> {
        if (source == null) return emptyList()
        val uris = mutableListOf<String>()
        source.getParcelableExtra<android.net.Uri>(Intent.EXTRA_STREAM)?.let { uris.add(it.toString()) }
        source.getParcelableArrayListExtra<android.net.Uri>(Intent.EXTRA_STREAM)?.let { list -> list.forEach { uris.add(it.toString()) } }
        return uris.distinct().mapNotNull { uri ->
            runCatching {
                val target = File(cacheDir, "shared_${System.nanoTime()}_${File(uri).name.ifBlank { "image" }}")
                contentResolver.openInputStream(android.net.Uri.parse(uri))?.use { input -> target.outputStream().use { output -> input.copyTo(output) } }
                target.absolutePath
            }.getOrNull()
        }
    }
}

