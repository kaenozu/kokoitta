package com.kaenozu.kokoitta_app

import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

@RunWith(AndroidJUnit4::class)
@Config(sdk = [Build.VERSION_CODES.TIRAMISU])
class MainActivityTest {

    @Test
    fun computeRequestId_sameContent_producesSameId() {
        val uri1 = Uri.parse("content://media/image.jpg")
        val uri2 = Uri.parse("content://media/image.jpg")
        val intent1 = Intent(Intent.ACTION_SEND).putExtra(Intent.EXTRA_STREAM, uri1)
        val intent2 = Intent(Intent.ACTION_SEND).putExtra(Intent.EXTRA_STREAM, uri2)
        val activity = ActivityScenario.launch(MainActivity::class.java)
        activity.onActivity { main ->
            val id1 = main.computeRequestId(intent1)
            val id2 = main.computeRequestId(intent2)
            assertEquals(
                "Same URI content must produce same requestId",
                id1, id2,
            )
        }
        activity.close()
    }

    @Test
    fun computeRequestId_differentContent_producesDifferentIds() {
        val uri1 = Uri.parse("content://media/image1.jpg")
        val uri2 = Uri.parse("content://media/image2.jpg")
        val intent1 = Intent(Intent.ACTION_SEND).putExtra(Intent.EXTRA_STREAM, uri1)
        val intent2 = Intent(Intent.ACTION_SEND).putExtra(Intent.EXTRA_STREAM, uri2)
        val activity = ActivityScenario.launch(MainActivity::class.java)
        activity.onActivity { main ->
            val id1 = main.computeRequestId(intent1)
            val id2 = main.computeRequestId(intent2)
            assertTrue(
                "Different URI content must produce different requestIds",
                id1 != id2,
            )
        }
        activity.close()
    }

    @Test
    fun computeRequestId_multipleUris_orderInsensitive() {
        val uris1 = listOf(Uri.parse("content://media/a.jpg"), Uri.parse("content://media/b.jpg"))
        val uris2 = listOf(Uri.parse("content://media/b.jpg"), Uri.parse("content://media/a.jpg"))
        val intent1 = Intent(Intent.ACTION_SEND_MULTIPLE).putParcelableArrayListExtra(
            Intent.EXTRA_STREAM, ArrayList(uris1),
        )
        val intent2 = Intent(Intent.ACTION_SEND_MULTIPLE).putParcelableArrayListExtra(
            Intent.EXTRA_STREAM, ArrayList(uris2),
        )
        val activity = ActivityScenario.launch(MainActivity::class.java)
        activity.onActivity { main ->
            val id1 = main.computeRequestId(intent1)
            val id2 = main.computeRequestId(intent2)
            assertEquals(
                "Multiple URI order must not affect requestId",
                id1, id2,
            )
        }
        activity.close()
    }

    @Test
    fun resolveExtension_jpegMime_returnsJpg() {
        val activity = ActivityScenario.launch(MainActivity::class.java)
        activity.onActivity { main ->
            assertEquals("jpg", main.resolveExtension("image/jpeg", null))
        }
        activity.close()
    }

    @Test
    fun resolveExtension_pngMime_returnsPng() {
        val activity = ActivityScenario.launch(MainActivity::class.java)
        activity.onActivity { main ->
            assertEquals("png", main.resolveExtension("image/png", null))
        }
        activity.close()
    }

    @Test
    fun resolveExtension_heicMime_returnsHeic() {
        val activity = ActivityScenario.launch(MainActivity::class.java)
        activity.onActivity { main ->
            assertEquals("heic", main.resolveExtension("image/heic", null))
        }
        activity.close()
    }

    @Test
    fun resolveExtension_unknownMimeWithoutImagePrefix_returnsNull() {
        val activity = ActivityScenario.launch(MainActivity::class.java)
        activity.onActivity { main ->
            assertNull(
                "application/octet-stream must not be accepted",
                main.resolveExtension("application/octet-stream", null),
            )
        }
        activity.close()
    }

    @Test
    fun resolveExtension_nullMime_returnsNull() {
        val activity = ActivityScenario.launch(MainActivity::class.java)
        activity.onActivity { main ->
            assertNull("null MIME must not be accepted", main.resolveExtension(null, "image.jpg"))
        }
        activity.close()
    }

    @Test
    fun resolveExtension_knownDisplayNameExtension_whenMimeIsImage() {
        val activity = ActivityScenario.launch(MainActivity::class.java)
        activity.onActivity { main ->
            assertEquals(
                "From displayName.webp with image/webp MIME",
                "webp",
                main.resolveExtension("image/webp", "photo.webp"),
            )
        }
        activity.close()
    }

    @Test
    fun resolveExtension_unknownDisplayNameExtension_withImageMime_returnsNull() {
        val activity = ActivityScenario.launch(MainActivity::class.java)
        activity.onActivity { main ->
            assertNull(
                "Display name with .xyz123abc extension and image MIME must be rejected",
                main.resolveExtension("image/jpeg", "photo.xyz123abc"),
            )
        }
        activity.close()
    }

    @Test
    fun consumeIntent_clearsStreamAndAction() {
        val intent = Intent(Intent.ACTION_SEND).putExtra(
            Intent.EXTRA_STREAM, Uri.parse("content://media/image.jpg"),
        )
        val activity = ActivityScenario.launch(MainActivity::class.java)
        activity.onActivity { main ->
            main.consumeIntent(intent)
            assertNull(intent.action)
            assertNull(intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM))
        }
        activity.close()
    }
}
