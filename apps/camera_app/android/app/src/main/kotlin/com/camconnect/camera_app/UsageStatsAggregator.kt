package com.camconnect.camera_app

import android.app.usage.UsageStats
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log

/**
 * รวม UsageStats 24 ชั่วโมงล่าสุด → list ของ app + เวลาใช้งาน
 * ต้องการ PACKAGE_USAGE_STATS permission (special — user grant via Settings)
 *
 * คืน List<Map> สำหรับส่งผ่าน MethodChannel กลับไป Flutter
 * - filter system app ที่ไม่มี launcher intent ออก
 * - filter own app ออก
 * - sort desc ตาม totalTimeForeground
 * - limit ที่ topN (default 15)
 */
object UsageStatsAggregator {

    private const val TAG = "UsageStats"

    fun read(context: Context, rangeMs: Long, topN: Int = 15): List<Map<String, Any?>> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) return emptyList()
        if (!DeviceStatusReader.hasUsageStatsPermission(context)) return emptyList()

        val usm = context.getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager
            ?: return emptyList()

        return try {
            val end = System.currentTimeMillis()
            val begin = end - rangeMs
            val raw = usm.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, begin, end)
                ?: return emptyList()

            // aggregate ซ้ำ — บางครั้ง queryUsageStats คืนหลาย entry ต่อ package
            val grouped = mutableMapOf<String, UsageStats>()
            for (s in raw) {
                val pkg = s.packageName ?: continue
                val existing = grouped[pkg]
                if (existing == null || s.totalTimeInForeground > existing.totalTimeInForeground) {
                    grouped[pkg] = s
                }
            }

            val pm = context.packageManager
            val ownPkg = context.packageName

            grouped.values
                .filter { it.totalTimeInForeground > 0 }
                .filter { it.packageName != ownPkg }
                .filter { hasLauncher(pm, it.packageName) }
                .sortedByDescending { it.totalTimeInForeground }
                .take(topN)
                .map { stat ->
                    mapOf<String, Any?>(
                        "packageName" to stat.packageName,
                        "appLabel" to (resolveLabel(pm, stat.packageName) ?: stat.packageName),
                        "totalTimeMs" to stat.totalTimeInForeground,
                        "lastUsed" to stat.lastTimeUsed,
                    )
                }
        } catch (e: Exception) {
            Log.w(TAG, "queryUsageStats failed: ${e.message}")
            emptyList()
        }
    }

    private fun hasLauncher(pm: PackageManager, pkg: String): Boolean {
        return try {
            pm.getLaunchIntentForPackage(pkg) != null
        } catch (e: Exception) {
            false
        }
    }

    private fun resolveLabel(pm: PackageManager, pkg: String): String? {
        return try {
            val info = pm.getApplicationInfo(pkg, 0)
            pm.getApplicationLabel(info).toString()
        } catch (e: Exception) {
            null
        }
    }
}
