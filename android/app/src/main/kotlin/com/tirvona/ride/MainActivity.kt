package com.tirvona.ride

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ContentResolver
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createAlertChannels()
    }

    /**
     * One high-importance channel per alert sound. Android plays the
     * channel's sound and cannot change it once the channel exists, so each
     * sound has its own channel id. The backend picks the channel per push
     * (notification-types.ts, PUSH_CHANNEL_IDS), and push_notifications.dart
     * creates the same channels for notifications shown while the app is
     * open. Creating an existing channel is a no-op.
     */
    private fun createAlertChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        // Earlier ids. A channel keeps the sound it was created with, and some
        // builds created these before the sound files shipped (silent), so the
        // ids moved on and the old channels are removed.
        for (old in listOf("tirvona_rides", "tirvona_rides_v2", "tirvona_ride_requests", "tirvona_sos"))
            manager.deleteNotificationChannel(old)

        val channels = listOf(
            Triple(RIDE_UPDATES_CHANNEL_ID, "Ride updates", "ride_update") to
                "Driver updates, payments and account notices",
            Triple(RIDE_REQUESTS_CHANNEL_ID, "New ride requests", "ride_request") to
                "A rider is asking for a ride",
            Triple(SOS_CHANNEL_ID, "Safety alerts", "sos_alert") to
                "SOS and safety alerts",
        )
        for ((spec, description) in channels) {
            val (id, name, sound) = spec
            val channel = NotificationChannel(id, name, NotificationManager.IMPORTANCE_HIGH).apply {
                this.description = description
                enableVibration(true)
                setSound(
                    Uri.parse("${ContentResolver.SCHEME_ANDROID_RESOURCE}://$packageName/raw/$sound"),
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
            }
            manager.createNotificationChannel(channel)
        }
    }

    private companion object {
        const val RIDE_UPDATES_CHANNEL_ID = "tirvona_rides_v3"
        const val RIDE_REQUESTS_CHANNEL_ID = "tirvona_ride_requests_v2"
        const val SOS_CHANNEL_ID = "tirvona_sos_v2"
    }
}
