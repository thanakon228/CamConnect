package com.camconnect.camera_app

import android.app.Notification
import android.content.Context
import android.content.pm.PackageManager
import android.os.Bundle
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log

/**
 * NotificationListenerService ดักจับ notification ที่เครื่องลูกได้รับ
 * แล้ว buffer ไว้ใน static queue ให้ Flutter drain ผ่าน MethodChannel
 *
 * Requires:
 * - permission BIND_NOTIFICATION_LISTENER_SERVICE (auto granted ในไฟล์ manifest)
 * - user enable ใน Settings → Notification access (manual grant)
 *
 * Buffer policy:
 * - ArrayDeque cap ที่ 100 ตัว — เก่าสุดถูกลบเมื่อเกิน
 * - thread-safe via @Synchronized (NotificationListener thread vs MethodChannel main thread)
 */
class CamConnectNotifListener : NotificationListenerService() {

    override fun onListenerConnected() {
        super.onListenerConnected()
        Log.i(TAG, "Notification listener connected")
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        Log.i(TAG, "Notification listener disconnected")
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        try {
            val event = build(sbn) ?: return
            push(event)
        } catch (e: Exception) {
            Log.w(TAG, "onNotificationPosted error: ${e.message}")
        }
    }

    /**
     * แปลง StatusBarNotification → NotifEvent map พร้อมส่ง
     * คืน null ถ้าควร skip (own app, group summary, no text)
     */
    private fun build(sbn: StatusBarNotification): Map<String, Any?>? {
        val pkg = sbn.packageName ?: return null

        // skip notification ของแอพตัวเอง (Google Play update notif, wake request, etc.)
        if (pkg == packageName) return null

        val notif: Notification = sbn.notification ?: return null
        val extras: Bundle = notif.extras ?: return null

        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()
            ?: extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()

        // ไม่มีทั้ง title และ text → skip (มักเป็น group summary, transport, etc.)
        if (title.isNullOrBlank() && text.isNullOrBlank()) return null

        val appLabel = resolveAppLabel(pkg) ?: pkg

        return mapOf(
            "id" to sbn.id,
            "key" to sbn.key,
            "packageName" to pkg,
            "appLabel" to appLabel,
            "title" to (title ?: ""),
            "text" to (text ?: ""),
            "postTime" to sbn.postTime,
        )
    }

    private fun resolveAppLabel(pkg: String): String? {
        return try {
            val info = packageManager.getApplicationInfo(pkg, 0)
            packageManager.getApplicationLabel(info).toString()
        } catch (e: PackageManager.NameNotFoundException) {
            null
        }
    }

    companion object {
        private const val TAG = "NotifListener"
        private const val MAX_BUFFER = 100

        // static buffer — shared ระหว่าง service และ MainActivity (same process)
        private val buffer = ArrayDeque<Map<String, Any?>>()
        private val lock = Any()

        private fun push(event: Map<String, Any?>) {
            synchronized(lock) {
                buffer.addLast(event)
                while (buffer.size > MAX_BUFFER) buffer.removeFirst()
            }
        }

        /**
         * ดึง notif events ที่ buffer ไว้ทั้งหมด + clear buffer
         * เรียกจาก Flutter ผ่าน MethodChannel ทุก ๆ N วินาที
         */
        fun drain(): List<Map<String, Any?>> {
            synchronized(lock) {
                if (buffer.isEmpty()) return emptyList()
                val out = buffer.toList()
                buffer.clear()
                return out
            }
        }

        /**
         * เช็คว่า user grant Notification Listener access แล้วหรือยัง
         * (Settings → Notification access → CamConnect)
         */
        fun isEnabled(context: Context): Boolean {
            val flat = Settings.Secure.getString(
                context.contentResolver,
                "enabled_notification_listeners",
            ) ?: return false
            val name = "${context.packageName}/${CamConnectNotifListener::class.java.name}"
            return flat.split(":").any { it == name }
        }
    }
}
