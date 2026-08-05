package com.kaenozu.kokoitta_app

import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SharedImageFormatValidatorTest {
    @Test
    fun detectsSupportedHeaders() {
        assertDetected(SharedImageFormat.JPEG, byteArrayOf(0xff.toByte(), 0xd8.toByte(), 0xff.toByte(), 0x00))
        assertDetected(SharedImageFormat.PNG, byteArrayOf(0x89.toByte(), 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a))
        assertDetected(SharedImageFormat.GIF, "GIF89a".toByteArray())
        assertDetected(SharedImageFormat.WEBP, "RIFF0000WEBP".toByteArray())
        assertDetected(SharedImageFormat.BMP, "BM".toByteArray())
        assertDetected(SharedImageFormat.HEIC, byteArrayOf(0, 0, 0, 24) + "ftypheic".toByteArray())
    }

    @Test
    fun rejectsFakeJpegAndDecodeFailure() {
        val nonImage = tempFile("not-an-image".toByteArray())
        val fake = SharedImageFormatValidator.validate(
  nonImage,
  "image/jpeg",
  "photo.jpg",
        ) { _, _ -> true }
        assertEquals("invalid_image", fake.errorCode)

        val corruptJpeg = tempFile(byteArrayOf(0xff.toByte(), 0xd8.toByte(), 0xff.toByte(), 0x00))
        val corrupt = SharedImageFormatValidator.validate(
  corruptJpeg,
  "image/jpeg",
  "photo.jpg",
        ) { _, _ -> false }
        assertEquals("decode_failed", corrupt.errorCode)
    }

    @Test
    fun rejectsMimeAndExtensionMismatch() {
        val png = tempFile(byteArrayOf(0x89.toByte(), 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a))
        val mimeMismatch = SharedImageFormatValidator.validate(
  png,
  "image/jpeg",
  "photo.png",
        ) { _, _ -> true }
        assertEquals("format_mismatch", mimeMismatch.errorCode)

        val extensionMismatch = SharedImageFormatValidator.validate(
  png,
  null,
  "photo.jpg",
        ) { _, _ -> true }
        assertEquals("format_mismatch", extensionMismatch.errorCode)
    }

    @Test
    fun acceptsHeaderWhenMimeAndExtensionAreMissing() {
        val png = tempFile(byteArrayOf(0x89.toByte(), 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a))
        val result = SharedImageFormatValidator.validate(png, null, null) { _, _ -> true }
        assertEquals(SharedImageFormat.PNG, result.format)
        assertNull(result.errorCode)
    }

    @Test
    fun rejectsExplicitlyUnsupportedImageTypes() {
        val payload = tempFile("<svg/>".toByteArray())
        for ((mime, name) in listOf(
  "image/svg+xml" to "photo.svg",
  "image/tiff" to "photo.tiff",
  "image/x-icon" to "photo.ico",
  "image/vnd.wap.wbmp" to "photo.wbmp",
        )) {
  val result = SharedImageFormatValidator.validate(payload, mime, name) { _, _ -> true }
  assertEquals("unsupported_format", result.errorCode)
        }
    }

    @Test
    fun claimContractOnlyIncludesSupportedFormats() {
        assertEquals(SharedImageFormat.JPEG, SharedImageFormatValidator.claimedFormat("image/jpeg", "x.bin"))
        assertEquals(SharedImageFormat.PNG, SharedImageFormatValidator.claimedFormat(null, "x.PNG"))
        assertNull(SharedImageFormatValidator.claimedFormat("image/svg+xml", "x.svg"))
        assertNull(SharedImageFormatValidator.claimedFormat(null, "x.tiff"))
    }

    private fun assertDetected(expected: SharedImageFormat, bytes: ByteArray) {
        assertEquals(expected, SharedImageFormatValidator.detect(tempFile(bytes)))
    }

    private fun tempFile(bytes: ByteArray): File {
        val file = Files.createTempFile("shared-image-format", ".bin").toFile()
        file.deleteOnExit()
        file.writeBytes(bytes)
        assertTrue(file.exists())
        return file
    }
}
