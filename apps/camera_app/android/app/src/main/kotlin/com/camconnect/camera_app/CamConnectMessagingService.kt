package com.camconnect.camera_app

import android.content.Intent
import android.util.Log
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/**
 * รับ FCM push เพื่อปลุก camera_app จากสถานะที่ process ตายอยู่
 *
 * เมื่อ Android ส่ง FCM message มา → FirebaseMessagingService จะ instantiate
 * service นี้ขึ้นมาแม้ process เคยตาย — ได้ BAL allowance สั้นๆ พอที่จะ
 * launch MainActivity ได้
 *
 * จำกัด: ถ้า user ทำ Force Stop ใน Settings → Android ไม่ส่ง push เลย
 */
class CamConnectMessagingService : FirebaseMessagingService() {

    override fun onMessageReceived(message: RemoteMessage) {
        val action = message.data["action"]
        Log.i(TAG, "FCM received: action=$action data=${message.data}")

        if (action == "wake-camera") {
            launchMainActivity()
        }
    }

    override fun onNewToken(token: String) {
        // Token อาจถูก rotate โดย Firebase — camera_app จะส่งใหม่ตอน register-camera
        Log.i(TAG, "New FCM token: ${token.substring(0, 12)}…")
    }

    private fun launchMainActivity() {
        val intent = Intent(this, MainActivity::class.java)
        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or
            Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED
        intent.putExtra(BootReceiver.EXTRA_AUTO_START, true)
        try {
            applicationContext.startActivity(intent)
            Log.i(TAG, "Launched MainActivity from FCM")
        } catch (e: Exception) {
            Log.w(TAG, "Failed to launch from FCM: ${e.message}")
        }
    }

    companion object {
        private const val TAG = "FCM"
    }
}
