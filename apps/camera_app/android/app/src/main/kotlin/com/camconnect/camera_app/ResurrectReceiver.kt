package com.camconnect.camera_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * รับ broadcast ที่ AlarmManager ตั้งไว้หลัง user ปัด app ทิ้งจาก Recent Tasks
 * แล้ว launch MainActivity เพื่อให้ Flutter รัน WebRTC + camera ต่อ
 *
 * เหตุผลที่ต้องผ่าน AlarmManager + Receiver แทนการ startActivity จาก service ตรงๆ:
 * - Android 12+ มี Background Activity Launch (BAL) restrictions ที่บล็อก
 *   service.startActivity() เกือบทุกกรณี
 * - แต่ broadcast receiver ที่ถูก trigger จาก system event (รวม AlarmManager)
 *   ได้รับ BAL allowance สั้นๆ (~10s) เพียงพอที่จะ launch activity ได้
 */
class ResurrectReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_RESURRECT) return

        Log.i(TAG, "Resurrecting activity after task removal")

        val launchIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED or
                Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(BootReceiver.EXTRA_AUTO_START, true)
        }
        try {
            context.startActivity(launchIntent)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to launch MainActivity: ${e.message}")
        }
    }

    companion object {
        private const val TAG = "ResurrectReceiver"
        const val ACTION_RESURRECT = "com.camconnect.camera_app.RESURRECT"
    }
}
