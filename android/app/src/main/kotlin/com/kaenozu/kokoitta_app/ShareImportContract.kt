package com.kaenozu.kokoitta_app

import java.io.InputStream
import java.io.OutputStream

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
