package com.zwjsg.zwjsg_app

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import android.os.Process
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.Calendar

/**
 * 读取当天的手机使用情况。
 * 隐私约定：具体 app 包名只在这里用于计算，返回给 Flutter 的只有分类汇总，不含任何 app 名称。
 */
class UsagePlugin(private val context: Context) {

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "zwjsg/usage").setMethodCallHandler { call, result ->
            when (call.method) {
                "hasPermission" -> result.success(hasPermission())
                "openPermissionSettings" -> {
                    val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(intent)
                    result.success(null)
                }
                "getTodayUsage" -> {
                    if (!hasPermission()) {
                        result.error("NO_PERMISSION", "未授权使用情况访问权限", null)
                    } else {
                        try {
                            result.success(todayUsage())
                        } catch (e: Exception) {
                            result.error("USAGE_FAILED", e.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun hasPermission(): Boolean {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName)
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName)
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun todayUsage(): Map<String, Any> {
        val usm = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val now = System.currentTimeMillis()
        val startOfDay = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }.timeInMillis
        val lateNightStart = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 23); set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }.timeInMillis

        val ignored = ignoredPackages()
        val foregroundMs = HashMap<String, Long>()
        var lateNightMs = 0L
        var pickups = 0

        var currentPkg: String? = null
        var currentStart = 0L

        fun closeSession(end: Long) {
            val pkg = currentPkg ?: return
            if (end > currentStart && pkg !in ignored) {
                foregroundMs[pkg] = (foregroundMs[pkg] ?: 0L) + (end - currentStart)
                val lateFrom = maxOf(currentStart, lateNightStart)
                if (end > lateFrom) lateNightMs += end - lateFrom
            }
            currentPkg = null
        }

        val resumed = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) UsageEvents.Event.ACTIVITY_RESUMED
        else @Suppress("DEPRECATION") UsageEvents.Event.MOVE_TO_FOREGROUND
        val paused = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) UsageEvents.Event.ACTIVITY_PAUSED
        else @Suppress("DEPRECATION") UsageEvents.Event.MOVE_TO_BACKGROUND

        val events = usm.queryEvents(startOfDay, now)
        val e = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(e)
            when (e.eventType) {
                resumed -> {
                    closeSession(e.timeStamp)
                    currentPkg = e.packageName
                    currentStart = e.timeStamp
                }
                paused -> if (e.packageName == currentPkg) closeSession(e.timeStamp)
                UsageEvents.Event.SCREEN_NON_INTERACTIVE -> closeSession(e.timeStamp)
                UsageEvents.Event.KEYGUARD_HIDDEN -> pickups++
            }
        }
        closeSession(now)

        val categoryMs = HashMap<String, Long>()
        for ((pkg, ms) in foregroundMs) {
            val cat = categoryOf(pkg)
            categoryMs[cat] = (categoryMs[cat] ?: 0L) + ms
        }

        val toMin = { ms: Long -> (ms / 60000L).toInt() }
        return mapOf(
            "totalMinutes" to toMin(foregroundMs.values.sum()),
            "pickups" to pickups,
            "lateNightMinutes" to toMin(lateNightMs),
            "categoryMinutes" to categoryMs.mapValues { toMin(it.value) },
        )
    }

    /** 自己、桌面启动器不计入使用时长 */
    private fun ignoredPackages(): Set<String> {
        val set = mutableSetOf(context.packageName)
        val home = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        context.packageManager.queryIntentActivities(home, PackageManager.MATCH_DEFAULT_ONLY)
            .forEach { set.add(it.activityInfo.packageName) }
        return set
    }

    /** 系统给 app 标的分类 → 我们的 5 类 */
    private fun categoryOf(pkg: String): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return "other"
        val info = try {
            context.packageManager.getApplicationInfo(pkg, 0)
        } catch (e: PackageManager.NameNotFoundException) {
            return "other"
        }
        return when (info.category) {
            ApplicationInfo.CATEGORY_VIDEO -> "video"
            ApplicationInfo.CATEGORY_SOCIAL -> "social"
            ApplicationInfo.CATEGORY_GAME -> "game"
            ApplicationInfo.CATEGORY_PRODUCTIVITY -> "productivity"
            else -> "other"
        }
    }
}
