package com.kaenozu.kokoitta_app

import android.content.Intent
import android.net.Uri
import java.io.InputStream
import java.io.OutputStream
import java.security.MessageDigest

/** Pure share-intent contract used by MainActivity and JVM tests. */
internal object ShareIntentContract {
    fun computeRequestId(intent: Intent): String {
        val singleUri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
        val multiUris = intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
        val allUris = (listOfNotNull(singleUri) + (multiUris ?: emptyList())).distinct().sorted()
        if (allUris.isEmpty()) return "empty_${intent.action}"
        val joined = allUris.joinToString("|") { it.toString().lowercase() }
        val digest = MessageDigest.getInstance("MD5").digest(joined.toByteArray())
        return digest.joinToString("") { "%02x".format(it) } + "_${intent.action}"
    }

    fun consumeIntent(intent: Intent) {
        intent.removeExtra(Intent.EXTRA_STREAM)
        intent.action = null
    }
}

internal enum class ImportPhase {
    PREPARING,
    COPYING,
    SAVING,
    COMPLETED,
    PARTIAL_FAILURE,
    FAILED,
    CANCELLED,
}

internal data class ImportProgressEvent(
    val requestId: String,
    val phase: ImportPhase,
    val processed: Int,
    val total: Int,
    val succeeded: Int,
    val failed: Int,
    val terminal: Boolean,
)

internal data class CopyOutcome(
    val bytesCopied: Long,
    val stopped: StopReason,
)

internal enum class StopReason {
    COMPLETED,
    CANCELLED,
    LIMIT_EXCEEDED,
}

/** Owns a single active share request. Old jobs cannot finish a newer request. */
internal class RequestOwnership {
    private var activeRequestId: String? = null
    private var activeGeneration: Long = 0L

    @Synchronized
    fun start(requestId: String): Long? {
        if (requestId.isEmpty() || requestId == activeRequestId) return null
        activeGeneration += 1L
        activeRequestId = requestId
        return activeGeneration
    }

    @Synchronized
    fun owns(requestId: String, generation: Long): Boolean =
        requestId == activeRequestId && generation == activeGeneration

    @Synchronized
    fun finish(requestId: String, generation: Long): Boolean {
        if (!owns(requestId, generation)) return false
        activeRequestId = null
        return true
    }

    @Synchronized
    fun cancel(requestId: String, generation: Long): Boolean =
        finish(requestId, generation)
}

/**
 * Issues a unique requestId for every share request.
 *
 * The base id is derived from the URI contents so that the same photo set maps
 * to the same base; appending a monotonic counter keeps re-sharing the same set
 * distinguishable from the previous delivery. Flutter-side terminal/cancelled
 * history is tracked per requestId, so a fresh id prevents a re-share from
 * being permanently rejected within a session.
 */
internal class ShareRequestIdGenerator {
    private var sequence = 0L

    fun next(baseRequestId: String): String {
        sequence += 1
        return "${baseRequestId}_s$sequence"
    }
}

/**
 * Holds share requests that arrived while another request was still active.
 *
 * A new share must neither cancel nor be dropped by the in-flight request.
 * Entries are processed strictly FIFO after the active session ends.
 */
internal class PendingShareQueue<T> {
    private val entries = ArrayDeque<T>()

    fun isEmpty(): Boolean = entries.isEmpty()

    fun enqueue(entry: T) {
        entries.addLast(entry)
    }

    /** Removes and returns the oldest entry, or null when empty. */
    fun pollFirst(): T? = if (entries.isEmpty()) null else entries.removeFirst()

    fun clear() {
        entries.clear()
    }
}

/** Copies a stream with a fixed buffer and stops before an upper bound is exceeded. */
internal object BoundedStreamCopier {
    private const val BUFFER_SIZE = 32 * 1024

    fun copy(
        input: InputStream,
        output: OutputStream,
        maxBytes: Long,
        isCancelled: () -> Boolean = { false },
    ): CopyOutcome {
        require(maxBytes >= 0) { "maxBytes must not be negative" }
        val buffer = ByteArray(BUFFER_SIZE)
        var copied = 0L
        while (true) {
            if (isCancelled()) return CopyOutcome(copied, StopReason.CANCELLED)
            val read = input.read(buffer)
            if (read < 0) return CopyOutcome(copied, StopReason.COMPLETED)
            if (read == 0) continue
            val remaining = maxBytes - copied
            if (remaining <= 0) return CopyOutcome(copied, StopReason.LIMIT_EXCEEDED)
            val writable = minOf(remaining, read.toLong()).toInt()
            output.write(buffer, 0, writable)
            copied += writable
            if (writable < read) return CopyOutcome(copied, StopReason.LIMIT_EXCEEDED)
        }
    }
}
