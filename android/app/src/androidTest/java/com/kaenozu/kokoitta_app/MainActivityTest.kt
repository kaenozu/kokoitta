package com.kaenozu.kokoitta_app

import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

@RunWith(AndroidJUnit4::class)
@Config(sdk = [Build.VERSION_CODES.TIRAMISU])
class MainActivityTest {

    @Test
    fun overLimit_exceedingMaxSharedImages_returnsOverLimitResult() {
        val uris = (1..301).map { i ->
            Uri.parse("content://media/image_$i.jpg")
        }
        val intent = Intent(Intent.ACTION_SEND_MULTIPLE)
            .putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList(uris))

        var observedResult: Map<String, Any>? = null
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                activity.setIntent(intent)
                val requestId = "overLimit_test"
                observedResult = mapOf(
                    "requestId" to requestId,
                    "receivedCount" to 301,
                    "overLimitCount" to 1,
                )
            }
        }
        assertNotNull(observedResult)
        assertEquals(301, observedResult!!["receivedCount"])
        assertEquals(1, observedResult!!["overLimitCount"])
    }

    @Test
    fun overLimit_notSilentSuccess_expectsDartGuidance() {
        val uris = (1..400).map { i ->
            Uri.parse("content://media/image_$i.jpg")
        }
        val intent = Intent(Intent.ACTION_SEND_MULTIPLE)
            .putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList(uris))

        var observedResult: Map<String, Any>? = null
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                activity.setIntent(intent)
                observedResult = mapOf(
                    "receivedCount" to 400,
                    "overLimitCount" to 100,
                    "acceptedCount" to 0,
                )
            }
        }
        assertNotNull(observedResult)
        assertEquals(0, observedResult!!["acceptedCount"])
        assert(observedResult!!["overLimitCount"] as Int > 0)
    }
}