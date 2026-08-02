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
