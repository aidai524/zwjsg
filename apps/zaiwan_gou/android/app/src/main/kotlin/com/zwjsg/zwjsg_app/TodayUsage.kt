package com.zwjsg.zwjsg_app

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
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

        /** 今天 0 点到现在 */
        fun compute(context: Context): TodayUsage {
            val startOfDay = dayStart(0)
            return computeRange(context, startOfDay, System.currentTimeMillis(), startOfDay + 23 * HOUR_MS).first
        }

        /**
         * [daysAgo] 天前那一整天（0 点到 24 点）。系统只留最近几天（一般 7–10 天）的使用记录，
         * 那天一条记录都没有时返回 null：说明数据已经被系统清掉了，不能当成“那天没用手机”。
         */
        fun computeDay(context: Context, daysAgo: Int): TodayUsage? {
            val start = dayStart(daysAgo)
            val end = dayStart(daysAgo - 1)
            val (usage, events) = computeRange(context, start, end, start + 23 * HOUR_MS)
            return if (events == 0) null else usage
        }

        /** [daysAgo] 天前的 0 点（本地时间）；0 是今天 0 点，-1 是明天 0 点 */
        fun dayStart(daysAgo: Int): Long = Calendar.getInstance().apply {
            add(Calendar.DAY_OF_YEAR, -daysAgo)
            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }.timeInMillis

        private const val HOUR_MS = 3_600_000L

        /** 一段时间里的使用情况，以及读到了几条系统记录 */
        private fun computeRange(context: Context, start: Long, end: Long, lateNightStart: Long): Pair<TodayUsage, Int> {
            val usm = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val now = end
            val startOfDay = start
            var eventCount = 0

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
                eventCount++
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

            return TodayUsage(foregroundMs, lateNightMs, pickups) to eventCount
        }

        /** 自己、桌面启动器不计入使用时长，也不能被锁 */
        fun ignoredPackages(context: Context): Set<String> {
            val set = mutableSetOf(context.packageName)
            val home = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
            context.packageManager.queryIntentActivities(home, PackageManager.MATCH_DEFAULT_ONLY)
                .forEach { set.add(it.activityInfo.packageName) }
            return set
        }

        /** 系统给 app 标的分类 → 我们的 5 类（狗度的犬种、超时来电的建议和选 App 时按类勾都用） */
        fun categoryOf(context: Context, pkg: String): String {
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
