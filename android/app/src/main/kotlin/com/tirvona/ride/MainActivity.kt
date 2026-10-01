package com.tirvona.ride

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createRideAlertsChannel()
    }

    /**
     * High-importance channel for ride and safety pushes, so "driver arrived"
     * and SOS updates show as heads-up banners. The backend sends every push
     * on this channel id (PUSH_ANDROID_CHANNEL_ID, default "tirvona_rides");
     * creating an existing channel is a no-op.
     */
    private fun createRideAlertsChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            RIDE_ALERTS_CHANNEL_ID,
            "Ride & safety alerts",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Driver updates, ride requests, payments and safety alerts"
            enableVibration(true)
        }
        getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
    }

    private companion object {
        const val RIDE_ALERTS_CHANNEL_ID = "tirvona_rides"
    }
}
