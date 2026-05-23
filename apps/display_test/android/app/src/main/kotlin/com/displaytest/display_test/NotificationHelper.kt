package com.displaytest.display_test

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * Helper สำหรับสร้าง notification หลายรูปแบบเพื่อทดสอบ
 *
 * channels:
 *   - test_default  → IMPORTANCE_DEFAULT (3)
 *   - test_high     → IMPORTANCE_HIGH (4) — heads-up banner
 *   - test_max      → IMPORTANCE_MAX (5) — heads-up + sound full
 */
object NotificationHelper {

    private var nextId = 1000

    fun ensureChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        listOf(
            Triple("test_default", "Test Default", NotificationManager.IMPORTANCE_DEFAULT),
            Triple("test_high", "Test High", NotificationManager.IMPORTANCE_HIGH),
            Triple("test_max", "Test Max", NotificationManager.IMPORTANCE_MAX),
        ).forEach { (id, name, importance) ->
            if (nm.getNotificationChannel(id) == null) {
                val ch = NotificationChannel(id, name, importance).apply {
                    description = "Sandbox test channel ($importance)"
                    enableVibration(true)
                    enableLights(true)
                    setShowBadge(true)
                }
                nm.createNotificationChannel(ch)
            }
        }
    }

    /**
     * Post notification ตาม params
     * @param channel "default" / "high" / "max"
     * @param style "standard" / "bigtext" / "bigpicture" / "inbox"
     * @param category "none" / "message" / "call" / "alarm" / "event"
     * @param actions จำนวน action buttons 0/1/2
     */
    fun post(
        context: Context,
        title: String,
        body: String,
        channel: String,
        style: String,
        category: String,
        actions: Int,
        sound: Boolean,
        vibrate: Boolean,
        autoCancel: Boolean,
    ) {
        ensureChannels(context)

        val channelId = when (channel) {
            "high" -> "test_high"
            "max" -> "test_max"
            else -> "test_default"
        }

        val priority = when (channel) {
            "high" -> NotificationCompat.PRIORITY_HIGH
            "max" -> NotificationCompat.PRIORITY_MAX
            else -> NotificationCompat.PRIORITY_DEFAULT
        }

        // intent ตอน tap → เปิด MainActivity
        val openIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pi = PendingIntent.getActivity(
            context, nextId, openIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        val builder = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(priority)
            .setContentIntent(pi)
            .setAutoCancel(autoCancel)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)

        if (category != "none") {
            builder.setCategory(
                when (category) {
                    "message" -> NotificationCompat.CATEGORY_MESSAGE
                    "call" -> NotificationCompat.CATEGORY_CALL
                    "alarm" -> NotificationCompat.CATEGORY_ALARM
                    "event" -> NotificationCompat.CATEGORY_EVENT
                    else -> NotificationCompat.CATEGORY_STATUS
                },
            )
        }

        var defaults = 0
        if (sound) defaults = defaults or Notification.DEFAULT_SOUND
        if (vibrate) defaults = defaults or Notification.DEFAULT_VIBRATE
        if (defaults != 0) builder.setDefaults(defaults)

        // Style
        when (style) {
            "bigtext" -> builder.setStyle(
                NotificationCompat.BigTextStyle().bigText(body)
            )
            "bigpicture" -> {
                // ใช้ ic_launcher เป็น placeholder
                val bm = android.graphics.BitmapFactory.decodeResource(
                    context.resources,
                    context.applicationInfo.icon,
                )
                builder.setStyle(
                    NotificationCompat.BigPictureStyle()
                        .bigPicture(bm)
                        .setBigContentTitle(title),
                )
            }
            "inbox" -> builder.setStyle(
                NotificationCompat.InboxStyle()
                    .setBigContentTitle(title)
                    .addLine("• บรรทัด 1: $body")
                    .addLine("• บรรทัด 2: รายการที่ 2")
                    .addLine("• บรรทัด 3: รายการที่ 3"),
            )
        }

        // Action buttons
        repeat(actions) { i ->
            val actionPI = PendingIntent.getActivity(
                context, nextId + 100 + i, openIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            builder.addAction(
                android.R.drawable.ic_menu_more,
                if (i == 0) "ปุ่ม A" else "ปุ่ม B",
                actionPI,
            )
        }

        val id = nextId++
        try {
            NotificationManagerCompat.from(context).notify(id, builder.build())
        } catch (e: SecurityException) {
            android.util.Log.w("NotificationHelper", "POST_NOTIFICATIONS not granted: ${e.message}")
        }
    }
}
