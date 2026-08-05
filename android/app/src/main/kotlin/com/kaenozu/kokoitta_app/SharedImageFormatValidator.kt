package com.kaenozu.kokoitta_app

import android.graphics.BitmapFactory
import android.os.Build
import java.io.File
import java.io.FileInputStream

internal enum class SharedImageFormat(
    val extension: String,
    val canonicalMimeType: String,
    val mimeTypes: Set<String>,
    val extensions: Set<String>,
) {
    JPEG("jpg", "image/jpeg", setOf("image/jpeg", "image/jpg"), setOf("jpg", "jpeg")),
    PNG("png", "image/png", setOf("image/png"), setOf("png")),
    WEBP("webp", "image/webp", setOf("image/webp"), setOf("webp")),
    GIF("gif", "image/gif", setOf("image/gif"), setOf("gif")),
    BMP("bmp", "image/bmp", setOf("image/bmp", "image/x-ms-bmp"), setOf("bmp")),
    HEIC(
        "heic",
        "image/heic",
        setOf("image/heic", "image/heif"),
        setOf("heic", "heif"),
    ),
}

internal data class SharedImageValidationResult(
    val format: SharedImageFormat? = null,
    val errorCode: String? = null,
    val reason: String? = null,
)

internal object SharedImageFormatValidator {
    private val unsupportedImageExtensions = setOf(
        "svg", "svgz", "tif", "tiff", "ico", "wbmp", "avif",
    )

    private val heifBrands = setOf(
        "heic", "heix", "hevc", "hevx", "heim", "heis", "heif", "mif1", "msf1",
    )

    fun claimedFormat(mimeType: String?, displayName: String?): SharedImageFormat? {
        val mime = mimeType?.trim()?.lowercase()
        val fromMime = SharedImageFormat.entries.firstOrNull { mime in it.mimeTypes }
        if (fromMime != null) return fromMime
        return formatFromExtension(displayName)
    }

    fun validate(
        file: File,
        declaredMimeType: String?,
        displayName: String?,
    ): SharedImageValidationResult = validate(
        file = file,
        declaredMimeType = declaredMimeType,
        displayName = displayName,
        canDecode = ::canPlatformDecode,
    )

    internal fun validate(
        file: File,
        declaredMimeType: String?,
        displayName: String?,
        canDecode: (File, SharedImageFormat) -> Boolean,
    ): SharedImageValidationResult {
        val mime = declaredMimeType?.trim()?.lowercase()
        if (mime != null && mime.startsWith("image/") &&
  SharedImageFormat.entries.none { mime in it.mimeTypes }
        ) {
  return SharedImageValidationResult(
      errorCode = "unsupported_format",
      reason = "未対応の画像MIMEです: $mime",
  )
        }

        val extension = extensionOf(displayName)
        if (extension in unsupportedImageExtensions) {
  return SharedImageValidationResult(
      errorCode = "unsupported_format",
      reason = "未対応の画像拡張子です: .$extension",
  )
        }

        val detected = detect(file)
  ?: return SharedImageValidationResult(
      errorCode = "invalid_image",
      reason = "画像ヘッダーを確認できませんでした",
  )

        val mimeClaim = SharedImageFormat.entries.firstOrNull { mime in it.mimeTypes }
        if (mimeClaim != null && mimeClaim != detected) {
  return SharedImageValidationResult(
      errorCode = "format_mismatch",
      reason = "宣言されたMIMEと実画像形式が一致しません",
  )
        }

        val extensionClaim = formatFromExtension(displayName)
        if (extensionClaim != null && extensionClaim != detected) {
  return SharedImageValidationResult(
      errorCode = "format_mismatch",
      reason = "ファイル名の拡張子と実画像形式が一致しません",
  )
        }

        if (!canDecode(file, detected)) {
  return SharedImageValidationResult(
      errorCode = "decode_failed",
      reason = "この端末では画像を安全にデコードできません",
  )
        }
        return SharedImageValidationResult(format = detected)
    }

    internal fun detect(file: File): SharedImageFormat? {
        val header = ByteArray(32)
        val length = try {
  FileInputStream(file).use { it.read(header) }
        } catch (_: Exception) {
  return null
        }
        if (length < 2) return null
        if (length >= 3 && u(header[0]) == 0xff && u(header[1]) == 0xd8 && u(header[2]) == 0xff) {
  return SharedImageFormat.JPEG
        }
        if (length >= 8 && header.copyOfRange(0, 8).contentEquals(
      byteArrayOf(0x89.toByte(), 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a),
  )
        ) {
  return SharedImageFormat.PNG
        }
        if (length >= 6) {
  val gif = ascii(header, 0, 6)
  if (gif == "GIF87a" || gif == "GIF89a") return SharedImageFormat.GIF
        }
        if (length >= 12 && ascii(header, 0, 4) == "RIFF" && ascii(header, 8, 4) == "WEBP") {
  return SharedImageFormat.WEBP
        }
        if (header[0] == 'B'.code.toByte() && header[1] == 'M'.code.toByte()) {
  return SharedImageFormat.BMP
        }
        if (length >= 12 && ascii(header, 4, 4) == "ftyp" && ascii(header, 8, 4) in heifBrands) {
  return SharedImageFormat.HEIC
        }
        return null
    }

    private fun canPlatformDecode(file: File, format: SharedImageFormat): Boolean {
        if (format == SharedImageFormat.HEIC && Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
  return false
        }
        return try {
  val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
  BitmapFactory.decodeFile(file.absolutePath, options)
  options.outWidth > 0 && options.outHeight > 0
        } catch (_: RuntimeException) {
  false
        } catch (_: OutOfMemoryError) {
  false
        }
    }

    private fun formatFromExtension(displayName: String?): SharedImageFormat? {
        val extension = extensionOf(displayName) ?: return null
        return SharedImageFormat.entries.firstOrNull { extension in it.extensions }
    }

    private fun extensionOf(displayName: String?): String? {
        val name = displayName?.trim() ?: return null
        val dot = name.lastIndexOf('.')
        if (dot < 0 || dot == name.lastIndex) return null
        return name.substring(dot + 1).lowercase()
    }

    private fun ascii(bytes: ByteArray, offset: Int, length: Int): String =
        bytes.copyOfRange(offset, offset + length).toString(Charsets.US_ASCII)

    private fun u(value: Byte): Int = value.toInt() and 0xff
}
