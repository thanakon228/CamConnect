package com.camconnect.camera_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * รับ BOOT_COMPLETED → launch MainActivity เพื่อให้ Flutter เริ่ม streaming อัตโนมัติ
 *
 * บน Android 12+ มี Background Activity Launch (BAL) restrictions แต่ broadcast receiver
 * ที่จับ BOOT_COMPLETED ยังได้รับ allowance ในการ launch activity (system event exemption)
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            "android.intent.action.QUICKBOOT_POWERON", // HTC/Samsung quickboot
            Intent.ACTION_LOCKED_BOOT_COMPLETED -> {
                Log.i(TAG, "Boot completed — launching MainActivity for auto-stream")
                launchMainActivity(context)
            }
        }
    }

    private fun launchMainActivity(context: Context) {
        val launchIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED
            putExtra(EXTRA_AUTO_START, true)
        }
        try {
            context.startActivity(launchIntent)
        } catch (e: Exception) {
            Log.w(TAG, "startActivity blocked (BAL?): ${e.message}")
        }
    }

    companion object {
        private const val TAG = "BootReceiver"
        const val EXTRA_AUTO_START = "auto_start"
    }
}
