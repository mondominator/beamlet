package com.beamlet.android.push

import android.app.PendingIntent
import android.content.Intent
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.beamlet.android.BeamletApplication
import com.beamlet.android.MainActivity
import com.beamlet.android.R
import com.beamlet.android.data.auth.AuthRepository
import com.beamlet.android.data.contacts.ContactRepository
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import javax.inject.Inject

@AndroidEntryPoint
class BeamletFirebaseService : FirebaseMessagingService() {

    @Inject
    lateinit var authRepository: AuthRepository

    @Inject
    lateinit var contactRepository: ContactRepository

    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onDestroy() {
        super.onDestroy()
        serviceScope.cancel()
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        Log.d("BeamletFCM", "New FCM token: $token")

        authRepository.storeFcmToken(token)

        // Register with server if authenticated
        if (authRepository.isAuthenticated) {
            serviceScope.launch {
                try {
                    contactRepository.registerDevice(token)
                    Log.d("BeamletFCM", "FCM token registered with server")
                } catch (e: Exception) {
                    Log.e("BeamletFCM", "Failed to register FCM token", e)
                }
            }
        }
    }

    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)
        Log.d("BeamletFCM", "Message received: ${message.data}")

        val data = message.data
        val senderName = data["sender_name"] ?: "Someone"
        val fileType = data["file_type"] ?: "file"
        val fileId = data["file_id"]

        val contentText = when {
            fileType.startsWith("image/") -> "$senderName sent you a photo"
            fileType.startsWith("video/") -> "$senderName sent you a video"
            fileType == "text" -> "$senderName sent you a message"
            fileType == "link" -> "$senderName sent you a link"
            else -> "$senderName sent you a file"
        }

        // Build intent that opens the app and navigates to the file
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            fileId?.let { putExtra(EXTRA_FILE_ID, it) }
        }

        val pendingIntent = PendingIntent.getActivity(
            this,
            fileId.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = NotificationCompat.Builder(this, BeamletApplication.CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentTitle("Beamlet")
            .setContentText(contentText)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        try {
            NotificationManagerCompat.from(this).notify(
                fileId?.hashCode() ?: System.currentTimeMillis().toInt(),
                notification,
            )
        } catch (e: SecurityException) {
            Log.e("BeamletFCM", "No notification permission", e)
        }
    }

    companion object {
        const val EXTRA_FILE_ID = "file_id"
    }
}
