package com.beamlet.android

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import dagger.hilt.android.HiltAndroidApp

@HiltAndroidApp
class BeamletApplication : Application() {

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Beamlet Inbox",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Notifications for received files and messages"
        }
        val notificationManager = getSystemService(NotificationManager::class.java)
        notificationManager.createNotificationChannel(channel)
    }

    companion object {
        const val CHANNEL_ID = "beamlet_inbox"
    }
}
