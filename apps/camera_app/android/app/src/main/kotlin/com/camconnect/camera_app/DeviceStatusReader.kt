package com.camconnect.camera_app

import android.app.AppOpsManager
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import android.os.Process
import android.telephony.SignalStrength
import android.telephony.TelephonyManager
import android.util.Log

/**
 * อ่านสถานะเครื่องลูก เพื่อรายงานให้ viewer (เครื่องแม่):
 * - battery level + charging
 * - network type (wifi / cellular / none) + signal level (0-4)
 * - foreground app ที่กำลังใช้อยู่ (ต้อง PACKAGE_USAGE_STATS permission)
 * - screen on/off
 *
 * คืน Map<String, Any?> สำหรับส่งผ่าน MethodChannel กลับไป Dart
 */
object DeviceStatusReader {

    private const val TAG = "DeviceStatusReader"

    fun read(context: Context): Map<String, Any?> {
        val battery = readBattery(context)
        val network = readNetwork(context)
        val foregroundApp = readForegroundApp(context)
        val screenOn = readScreenOn(context)

        return mapOf(
            "batteryLevel" to battery.first,
            "batteryCharging" to battery.second,
            "networkType" to network.first,
            "signalLevel" to network.second,
            "foregroundApp" to foregroundApp,
            "screenOn" to screenOn,
        )
    }

    /**
     * เช็คว่ามี PACKAGE_USAGE_STATS permission หรือยัง
     * (Special permission — user ต้อง grant manual ผ่าน Settings)
     */
    fun hasUsageStatsPermission(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) return false
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                context.packageName,
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                context.packageName,
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    // ---- private readers ----

    private fun readBattery(context: Context): Pair<Int, Boolean> {
        val bm = context.getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
            ?: return Pair(-1, false)
        val level = try {
            bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        } catch (e: Exception) {
            -1
        }
        val charging = try {
            bm.isCharging
        } catch (e: Exception) {
            false
        }
        return Pair(level, charging)
    }

    /**
     * คืน (networkType, signalLevel)
     * - networkType: "wifi" | "cellular" | "none"
     * - signalLevel: 0-4 (จำนวนขีด) หรือ -1 = ไม่ทราบ
     */
    private fun readNetwork(context: Context): Pair<String, Int> {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return Pair("none", -1)

        val activeNetwork = cm.activeNetwork ?: return Pair("none", -1)
        val caps = cm.getNetworkCapabilities(activeNetwork) ?: return Pair("none", -1)

        return when {
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> {
                Pair("wifi", readWifiSignal(context))
            }
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> {
                Pair("cellular", readCellularSignal(context))
            }
            else -> Pair("none", -1)
        }
    }

    private fun readWifiSignal(context: Context): Int {
        val wm = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            ?: return -1
        try {
            val info = wm.connectionInfo ?: return -1
            val rssi = info.rssi
            // RSSI: -100 (แย่) ถึง -50 (ดีมาก) → map เป็น 0-4 ขีด
            return WifiManager.calculateSignalLevel(rssi, 5)
        } catch (e: Exception) {
            Log.w(TAG, "WiFi signal read failed: ${e.message}")
            return -1
        }
    }

    private fun readCellularSignal(context: Context): Int {
        if (context.checkSelfPermission(android.Manifest.permission.READ_PHONE_STATE)
            != PackageManager.PERMISSION_GRANTED
        ) return -1
        val tm = context.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
            ?: return -1
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val ss: SignalStrength? = tm.signalStrength
                // level: 0 (no signal) ถึง 4 (great)
                return ss?.level ?: -1
            }
            return -1
        } catch (e: Exception) {
            Log.w(TAG, "Cellular signal read failed: ${e.message}")
            return -1
        }
    }

    /**
     * ใช้ UsageStatsManager หา package ที่ใช้งานล่าสุด 60 วินาที
     * คืน app label (เช่น "YouTube") ไม่ใช่ package name
     */
    private fun readForegroundApp(context: Context): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) return null
        if (!hasUsageStatsPermission(context)) return null

        val usm = context.getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager
            ?: return null
        try {
            val end = System.currentTimeMillis()
            val begin = end - 60_000L // ย้อน 60 วินาที
            val stats = usm.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, begin, end)
            if (stats.isNullOrEmpty()) return null

            // หา package ที่ lastTimeUsed สูงสุด
            val recent = stats.maxByOrNull { it.lastTimeUsed } ?: return null
            // กรอง launcher / system / camera_app เอง — ไม่ใช่ "แอพที่ user ใช้"
            val pkg = recent.packageName
            if (pkg == context.packageName) return "CamConnect (own)"

            return resolveAppLabel(context, pkg) ?: pkg
        } catch (e: Exception) {
            Log.w(TAG, "Foreground app read failed: ${e.message}")
            return null
        }
    }

    private fun resolveAppLabel(context: Context, packageName: String): String? {
        return try {
            val pm = context.packageManager
            val info = pm.getApplicationInfo(packageName, 0)
            pm.getApplicationLabel(info).toString()
        } catch (e: Exception) {
            null
        }
    }

    private fun readScreenOn(context: Context): Boolean {
        val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            ?: return false
        return try {
            pm.isInteractive
        } catch (e: Exception) {
            false
        }
    }
}
