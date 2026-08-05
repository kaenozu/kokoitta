# Shared image format contract

Android share import accepts only formats that are both identified from file bytes and decodable by the current Android platform without allocating the full bitmap.

| Format | MIME aliases | Extensions | Header check |
| --- | --- | --- | --- |
| JPEG | `image/jpeg`, `image/jpg` | `.jpg`, `.jpeg` | `FF D8 FF` |
| PNG | `image/png` | `.png` | PNG 8-byte signature |
| WebP | `image/webp` | `.webp` | RIFF container with `WEBP` brand |
| GIF | `image/gif` | `.gif` | `GIF87a` or `GIF89a` |
| BMP | `image/bmp`, `image/x-ms-bmp` | `.bmp` | `BM` |
| HEIC/HEIF | `image/heic`, `image/heif` | `.heic`, `.heif` | ISO-BMFF `ftyp` with a supported HEIF brand; Android 9+ |

SVG, TIFF, ICO, WBMP and AVIF are rejected. They previously passed MIME/extension checks even though the app had no guaranteed rendering contract for them.

The actual header is authoritative. A supported declared MIME or supported filename extension must agree with the detected bytes. A missing MIME and extension is allowed only when the bytes identify a supported format and Android can read valid image bounds. Corrupt files, fake MIME values and platform decode failures are reported per file without aborting other shared images.

Full-screen display remains bounded separately by the 4096-pixel decode ceiling. Original files are copied into app-private storage and are never overwritten in place.
