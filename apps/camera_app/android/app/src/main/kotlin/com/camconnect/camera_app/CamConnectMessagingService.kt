package com.camconnect.camera_app

import android.app.PendingIntent
import android.content.Intent
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/**
 * รับ FCM data message แล้ว manual post notification เพื่อให้ทำงานสม่ำเสมอ:
 * - App foreground: onMessageReceived ถูกเรียก → post notification → user เห็น
 * - App background (alive): onMessageReceived ถูกเรียก → post notification → user เห็น
 * - App killed (memory/battery): onMessageReceived ถูกเรียก → post notification → user เห็น
 * - App force-stopped: Android block FCM ทั้งหมด — ไม่มีทาง
 *
 * ใช้ data-only payload (notification field ใน FCM payload ทำให้ Android handle
 * auto-display ซึ่งไม่ consistent ทุก state)
 */
class CamConnectMessagingService : FirebaseMessagingService() {

    override fun onCreate() {
        super.onCreate()
        MainActivity.createWakeRequestChannel(applicationContext)
    }

    override fun onMessageReceived(message: RemoteMessage) {
        val data = message.data
        Log.i(TAG, "FCM received: data=$data")

        if (data["action"] == "wake-camera") {
            val title = data["title"] ?: "เครื่องแม่ขอเปิดกล้อง"
            val body = data["body"] ?: "แตะเพื่ออนุญาตเปิดกล้อง"
            postWakeNotification(title, body)
        }
    }

    override fun onNewToken(token: String) {
        Log.i(TAG, "New FCM token: ${token.substring(0, 12)}…")
    }

    /**
     * Post heads-up notification ที่ user แตะแล้วเปิด MainActivity
     */
    private fun postWakeNotification(title: String, body: String) {
        // Intent ที่เปิด MainActivity เมื่อ user แตะ notification
        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(BootReceiver.EXTRA_AUTO_START, true)
        }
        val contentPI = PendingIntent.getActivity(
            this,
            NOTIFICATION_ID,
            openIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        val notif = NotificationCompat.Builder(this, MainActivity.WAKE_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_HIGH) // heads-up บน Android < 8
            .setCategory(NotificationCompat.CATEGORY_CALL) // ดังเหมือนสายโทร
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(contentPI)
            .setAutoCancel(true)
            .setOngoing(false)
            .setDefaults(NotificationCompat.DEFAULT_ALL) // sound + vibrate + lights
            .build()

        try {
            NotificationManagerCompat.from(this).notify(NOTIFICATION_ID, notif)
            Log.i(TAG, "Posted wake notification")
        } catch (e: SecurityException) {
            // POST_NOTIFICATIONS ยังไม่ได้รับสิทธิ์ (Android 13+)
            Log.w(TAG, "Cannot post notification: ${e.message}")
        }
    }

    companion object {
        private const val TAG = "FCM"
        private const val NOTIFICATION_ID = 2001
    }
}
