package com.displaytest.display_test

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
 * Foreground service ที่จัดการ overlay window
 *
 * Action:
 *  - SHOW  → add/update view ด้วย params จาก intent extras
 *  - HIDE  → remove view + stopSelf
 *
 * Params (intent extras):
 *  - width, height (px)
 *  - x, y (top-left offset px)
 *  - alpha (0-1 float)
 *  - color (ARGB int)
 *  - touchable (boolean)
 */
class OverlayService : Service() {

    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    private var currentParams: WindowManager.LayoutParams? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        startAsForeground()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_SHOW -> handleShow(intent)
            ACTION_HIDE -> {
                handleHide()
                stopSelf()
                return START_NOT_STICKY
            }
        }
        return START_STICKY
    }

    private fun handleShow(intent: Intent) {
        val width = intent.getIntExtra(EXTRA_WIDTH, 200)
        val height = intent.getIntExtra(EXTRA_HEIGHT, 200)
        val x = intent.getIntExtra(EXTRA_X, 0)
        val y = intent.getIntExtra(EXTRA_Y, 0)
        val alpha = intent.getFloatExtra(EXTRA_ALPHA, 1.0f)
        val color = intent.getIntExtra(EXTRA_COLOR, Color.RED)
        val touchable = intent.getBooleanExtra(EXTRA_TOUCHABLE, false)

        Log.i(TAG, "show: ${width}x${height} @($x,$y) alpha=$alpha touchable=$touchable")

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        var flagsBits = WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
            WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS

        if (!touchable) {
            flagsBits = flagsBits or
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
        }

        val params = WindowManager.LayoutParams(
            width,
            height,
            type,
            flagsBits,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            this.x = x
            this.y = y
            this.alpha = alpha
        }

        currentParams = params

        if (overlayView == null) {
            // สร้าง view ใหม่
            val v = View(this).apply { setBackgroundColor(color) }
            overlayView = v
            try {
                windowManager?.addView(v, params)
            } catch (e: Exception) {
                Log.e(TAG, "addView failed: ${e.message}")
            }
        } else {
            // update existing
            overlayView?.setBackgroundColor(color)
            try {
                windowManager?.updateViewLayout(overlayView, params)
            } catch (e: Exception) {
                Log.e(TAG, "updateViewLayout failed: ${e.message}")
            }
        }
    }

    private fun handleHide() {
        Log.i(TAG, "hide")
        overlayView?.let {
            try { windowManager?.removeView(it) } catch (e: Exception) {
                Log.w(TAG, "removeView: ${e.message}")
            }
        }
        overlayView = null
    }

    override fun onDestroy() {
        handleHide()
        super.onDestroy()
    }

    private fun startAsForeground() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                nm.createNotificationChannel(
                    NotificationChannel(CHANNEL_ID, "Overlay test", NotificationManager.IMPORTANCE_LOW),
                )
            }
        }
        val notif = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_view)
            .setContentTitle("Overlay test")
            .setContentText("กำลังทดสอบ overlay window")
            .setOngoing(true)
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
        private const val TAG = "OverlayService"
        private const val CHANNEL_ID = "overlay_test_fgs"
        private const val NOTIFICATION_ID = 9001

        const val ACTION_SHOW = "com.displaytest.SHOW_OVERLAY"
        const val ACTION_HIDE = "com.displaytest.HIDE_OVERLAY"

        const val EXTRA_WIDTH = "w"
        const val EXTRA_HEIGHT = "h"
        const val EXTRA_X = "x"
        const val EXTRA_Y = "y"
        const val EXTRA_ALPHA = "alpha"
        const val EXTRA_COLOR = "color"
        const val EXTRA_TOUCHABLE = "touchable"
    }
}
