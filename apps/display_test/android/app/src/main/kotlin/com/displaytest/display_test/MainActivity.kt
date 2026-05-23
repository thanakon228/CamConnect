package com.displaytest.display_test

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName = "com.displaytest.display_test/platform"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        NotificationHelper.ensureChannels(this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "sendNotification" -> {
                        val args = call.arguments as Map<*, *>
                        NotificationHelper.post(
                            this,
                            title = args["title"] as? String ?: "Test",
                            body = args["body"] as? String ?: "Body",
                            channel = args["channel"] as? String ?: "default",
                            style = args["style"] as? String ?: "standard",
                            category = args["category"] as? String ?: "none",
                            actions = (args["actions"] as? Int) ?: 0,
                            sound = args["sound"] as? Boolean ?: true,
                            vibrate = args["vibrate"] as? Boolean ?: true,
                            autoCancel = args["autoCancel"] as? Boolean ?: true,
                        )
                        result.success(true)
                    }
                    "ensureNotificationPermission" -> {
                        ensureNotificationPermission()
                        result.success(true)
                    }
                    "showOverlay" -> {
                        val args = call.arguments as Map<*, *>
                        val intent = Intent(this, OverlayService::class.java).apply {
                            action = OverlayService.ACTION_SHOW
                            putExtra(OverlayService.EXTRA_WIDTH, (args["width"] as? Int) ?: 200)
                            putExtra(OverlayService.EXTRA_HEIGHT, (args["height"] as? Int) ?: 200)
                            putExtra(OverlayService.EXTRA_X, (args["x"] as? Int) ?: 0)
                            putExtra(OverlayService.EXTRA_Y, (args["y"] as? Int) ?: 0)
                            putExtra(
                                OverlayService.EXTRA_ALPHA,
                                ((args["alpha"] as? Number)?.toFloat()) ?: 1.0f,
                            )
                            putExtra(OverlayService.EXTRA_COLOR, (args["color"] as? Int) ?: -65536)
                            putExtra(
                                OverlayService.EXTRA_TOUCHABLE,
                                args["touchable"] as? Boolean ?: false,
                            )
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    }
                    "hideOverlay" -> {
                        val intent = Intent(this, OverlayService::class.java).apply {
                            action = OverlayService.ACTION_HIDE
                        }
                        startService(intent)
                        result.success(true)
                    }
                    "hasOverlayPermission" -> {
                        val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            Settings.canDrawOverlays(this)
                        } else true
                        result.success(granted)
                    }
                    "requestOverlayPermission" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
                            !Settings.canDrawOverlays(this)
                        ) {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:$packageName"),
                            )
                            startActivity(intent)
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

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
            1,
        )
    }
}
