package com.camconnect.camera_app

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
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
                    CameraStreamingService.start(this)
                    result.success(true)
                }
                "stopCameraService" -> {
                    CameraStreamingService.stop(this)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
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

    companion object {
        private const val REQUEST_CODE_POST_NOTIFICATIONS = 1
    }
}
