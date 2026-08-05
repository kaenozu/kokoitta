package com.kaenozu.kokoitta_app

import android.content.Intent
import android.net.Uri
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [34])
class MainActivityContractTest {
    @Test
    fun productionActivityComputesStableIdAndPreservesUriOrderIndependence() {
        val first = Intent(Intent.ACTION_SEND_MULTIPLE).apply {
            putParcelableArrayListExtra(
                Intent.EXTRA_STREAM,
                arrayListOf(Uri.parse("content://photos/two"), Uri.parse("content://photos/one")),
            )
        }
        val second = Intent(Intent.ACTION_SEND_MULTIPLE).apply {
            putParcelableArrayListExtra(
                Intent.EXTRA_STREAM,
                arrayListOf(Uri.parse("content://photos/one"), Uri.parse("content://photos/two")),
            )
        }

        assertEquals(ShareIntentContract.computeRequestId(first), ShareIntentContract.computeRequestId(second))
        assertTrue(ShareIntentContract.computeRequestId(first).endsWith("_android.intent.action.SEND_MULTIPLE"))
    }

    @Test
    fun productionActivityConsumesSharedIntent() {
        val intent = Intent(Intent.ACTION_SEND).apply {
            putExtra(Intent.EXTRA_STREAM, Uri.parse("content://photos/one"))
        }

        ShareIntentContract.consumeIntent(intent)

        assertNull(intent.action)
        assertTrue(!intent.hasExtra(Intent.EXTRA_STREAM))
    }

    @Test
    fun productionExtensionContractRejectsUnsupportedFormats() {
        val activity = MainActivity()
        assertEquals("jpg", activity.resolveExtension("image/jpeg", "photo.bin"))
        assertEquals("png", activity.resolveExtension(null, "photo.PNG"))
        assertNull(activity.resolveExtension("image/svg+xml", "photo.svg"))
        assertNull(activity.resolveExtension("image/tiff", "photo.tiff"))
        assertNull(activity.resolveExtension("image/x-icon", "photo.ico"))
    }
}
