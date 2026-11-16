package com.zwjsg.zwjsg_app

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Build
import android.os.Process
import java.io.ByteArrayOutputStream
import java.util.Calendar

/**
 * 当天的使用情况：各 app 的前台时长（毫秒）、23 点后时长、拿起次数。
 * 狗度、今日排行、App 时间锁共用。只在手机上用，不上传。
 */
class TodayUsage private constructor(
    val foregroundMs: Map<String, Long>,
    val lateNightMs: Long,
    val pickups: Int,
) {
    companion object {
        fun toMin(ms: Long) = (ms / 60000L).toInt()

        /** 有没有“使用情况访问权限” */
        fun hasPermission(context: Context): Boolean {
            val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                appOps.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName)
            } else {
                @Suppress("DEPRECATION")
                appOps.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName)
            }
            return mode == AppOpsManager.MODE_ALLOWED
        }

        fun compute(context: Context): TodayUsage {
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

            val ignored = ignoredPackages(context)
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

            return TodayUsage(foregroundMs, lateNightMs, pickups)
        }

        /** 自己、桌面启动器不计入使用时长，也不能被锁 */
        fun ignoredPackages(context: Context): Set<String> {
            val set = mutableSetOf(context.packageName)
            val home = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
            context.packageManager.queryIntentActivities(home, PackageManager.MATCH_DEFAULT_ONLY)
                .forEach { set.add(it.activityInfo.packageName) }
            return set
        }

        fun label(context: Context, pkg: String): String {
            val pm = context.packageManager
            return try {
                pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
            } catch (e: PackageManager.NameNotFoundException) {
                pkg // 今天用过、后来卸载了
            }
        }

        /** app 图标转成 [size]px 的 PNG；拿不到时为 null */
        fun iconPng(context: Context, pkg: String, size: Int = 96): ByteArray? = try {
            val drawable = context.packageManager.getApplicationIcon(pkg)
            val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            drawable.setBounds(0, 0, size, size)
            drawable.draw(Canvas(bitmap))
            ByteArrayOutputStream().use { out ->
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
                out.toByteArray()
            }
        } catch (e: Exception) {
            null
        }
    }
}
