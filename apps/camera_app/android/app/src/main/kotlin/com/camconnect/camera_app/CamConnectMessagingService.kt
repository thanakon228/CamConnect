package com.camconnect.camera_app

import android.util.Log
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/**
 * รับ FCM push เพื่อแสดง notification ขอเปิดกล้องจากแม่
 *
 * Flow:
 * 1. Server ส่ง FCM { notification: {title, body}, data: {action: wake-camera} }
 * 2. ถ้า app ตาย → Android แสดง heads-up notification เอง (จาก payload)
 *    user tap → เปิด MainActivity → auto-stream เริ่ม
 * 3. ถ้า app alive → onMessageReceived ที่นี่ทำงาน
 *    เราไม่ auto-launch ตามคำขอ user — ให้ tap notification เพื่อ explicit consent
 *
 * Limit: Force Stop → Android ไม่ deliver FCM เลย (security feature)
 */
class CamConnectMessagingService : FirebaseMessagingService() {

    override fun onCreate() {
        super.onCreate()
        // สร้าง notification channel ทันทีที่ service ถูก instantiate
        // — กันเคส FCM มาก่อน user เปิด MainActivity ครั้งแรก
        MainActivity.createWakeRequestChannel(applicationContext)
    }

    override fun onMessageReceived(message: RemoteMessage) {
        Log.i(TAG, "FCM received: notification=${message.notification?.title} data=${message.data}")
        // ไม่ auto-launch — รอ user tap notification เพื่อ consent
        // (Android handle notification display อัตโนมัติจาก notification payload)
    }

    override fun onNewToken(token: String) {
        Log.i(TAG, "New FCM token: ${token.substring(0, 12)}…")
    }

    companion object {
        private const val TAG = "FCM"
    }
}
