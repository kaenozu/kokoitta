package com.kaenozu.kokoitta_app

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ShareImportContractTest {
    @Test
    fun oldRequestCannotFinishNewRequest() {
        val ownership = RequestOwnership()
        val generationA = ownership.start("request-a")!!
        val generationB = ownership.start("request-b")!!

        assertFalse(ownership.finish("request-a", generationA))
        assertTrue(ownership.owns("request-b", generationB))
        assertTrue(ownership.finish("request-b", generationB))
        assertFalse(ownership.owns("request-b", generationB))
    }

    @Test
    fun sameRequestCannotStartTwice() {
        val ownership = RequestOwnership()
        assertTrue(ownership.start("request-a") != null)
        assertTrue(ownership.start("request-a") == null)
    }

    @Test
    fun requestIdGeneratorProducesUniqueIdsForTheSameBase() {
        val generator = ShareRequestIdGenerator()
        val first = generator.next("base-id")
        val second = generator.next("base-id")
        val third = generator.next("base-id")

        assertFalse(first == second)
        assertFalse(second == third)
        assertTrue(first.endsWith("_s1"))
        assertTrue(second.endsWith("_s2"))
        assertTrue(third.endsWith("_s3"))
    }

    @Test
    fun pendingShareQueueProcessesEntriesInFifoOrder() {
        val queue = PendingShareQueue<String>()
        assertTrue(queue.isEmpty())

        queue.enqueue("first")
        queue.enqueue("second")
        queue.enqueue("third")

        val order = mutableListOf<String>()
        while (true) {
            val next = queue.pollFirst() ?: break
            order += next
        }
        assertEquals(listOf("first", "second", "third"), order)
        assertTrue(queue.isEmpty())
        assertTrue(queue.pollFirst() == null)
    }

    @Test
    fun pendingShareQueueClearDropsAllEntries() {
        val queue = PendingShareQueue<String>()
        queue.enqueue("first")
        queue.enqueue("second")
        queue.clear()

        assertTrue(queue.isEmpty())
        assertTrue(queue.pollFirst() == null)
    }

    @Test
    fun boundedCopyStopsAtLimitAndWritesOnlyAllowedBytes() {
        val output = ByteArrayOutputStream()
        val outcome = BoundedStreamCopier.copy(
            ByteArrayInputStream(ByteArray(10) { it.toByte() }),
            output,
            maxBytes = 4,
        )

        assertEquals(4L, outcome.bytesCopied)
        assertEquals(StopReason.LIMIT_EXCEEDED, outcome.stopped)
        assertEquals(4, output.size())
    }

    @Test
    fun boundedCopyStopsWhenCancelledBeforeNextRead() {
        val output = ByteArrayOutputStream()
        val outcome = BoundedStreamCopier.copy(
            ByteArrayInputStream(ByteArray(10)),
            output,
            maxBytes = 20,
            isCancelled = { true },
        )

        assertEquals(0L, outcome.bytesCopied)
        assertEquals(StopReason.CANCELLED, outcome.stopped)
        assertEquals(0, output.size())
    }
}
