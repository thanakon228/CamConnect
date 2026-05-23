package com.camconnect.camera_app

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Device Admin Receiver — ทำให้ camera_app ถูกตั้งเป็น Device Owner ได้
 *
 * เมื่อตั้งเป็น Device Owner แล้ว (ผ่าน adb dpm set-device-owner):
 * - ปุ่ม Force Stop ใน Settings จะ greyed out
 * - ลบ app ไม่ได้
 * - app กลายเป็น "device controller" ระดับเดียวกับ MDM apps
 *
 * วิธีตั้ง (one-time, ผ่าน USB ADB):
 *   adb shell dpm set-device-owner com.camconnect.camera_app/.CamConnectDeviceAdminReceiver
 *
 * วิธีถอด:
 *   adb shell dpm remove-active-admin com.camconnect.camera_app/.CamConnectDeviceAdminReceiver
 */
class CamConnectDeviceAdminReceiver : DeviceAdminReceiver() {

    override fun onEnabled(context: Context, intent: Intent) {
        super.onEnabled(context, intent)
        Log.i(TAG, "Device Admin enabled — app is now protected from Force Stop")
    }

    override fun onDisabled(context: Context, intent: Intent) {
        super.onDisabled(context, intent)
        Log.i(TAG, "Device Admin disabled — app is no longer protected")
    }

    companion object {
        private const val TAG = "CamConnectDeviceAdmin"
    }
}
