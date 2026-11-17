package com.zwjsg.zwjsg_app

import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * 读取当天的手机使用情况。
 * 隐私约定：getTodayUsage 给狗度和上报用，只有分类汇总，不含任何 app 名称；
 * getTodayRanking 把各 app 的名称、图标和用时交给 Flutter，只在手机上显示今日排行，绝不上传。
 */
class UsagePlugin(private val context: Context) {

    private val mainHandler = Handler(Looper.getMainLooper())

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "zwjsg/usage").setMethodCallHandler { call, result ->
            when (call.method) {
                "getTodayRanking" -> {
                    if (!TodayUsage.hasPermission(context)) {
                        result.error("NO_PERMISSION", "未授权使用情况访问权限", null)
                    } else {
                        // 要读每个 app 的名称和图标，放到后台线程，结果回主线程
                        Thread {
                            val ranking = runCatching { todayRanking() }
                            mainHandler.post {
                                ranking.fold(
                                    { result.success(it) },
                                    { result.error("USAGE_FAILED", it.message, null) },
                                )
                            }
                        }.start()
                    }
                }
                "hasPermission" -> result.success(TodayUsage.hasPermission(context))
                "openPermissionSettings" -> {
                    val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(intent)
                    result.success(null)
                }
                "getTodayUsage" -> {
                    if (!TodayUsage.hasPermission(context)) {
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

    private fun todayUsage(): Map<String, Any> {
        val today = TodayUsage.compute(context)
        val categoryMs = HashMap<String, Long>()
        for ((pkg, ms) in today.foregroundMs) {
            val cat = categoryOf(pkg)
            categoryMs[cat] = (categoryMs[cat] ?: 0L) + ms
        }
        return mapOf(
            "totalMinutes" to TodayUsage.toMin(today.foregroundMs.values.sum()),
            "pickups" to today.pickups,
            "lateNightMinutes" to TodayUsage.toMin(today.lateNightMs),
            "categoryMinutes" to categoryMs.mapValues { TodayUsage.toMin(it.value) },
        )
    }

    /** 今日排行：用时最多的前 [limit] 个 app，不到 1 分钟的不算 */
    private fun todayRanking(limit: Int = 30): List<Map<String, Any?>> =
        TodayUsage.compute(context).foregroundMs.entries
            .filter { it.value >= 60_000L }
            .sortedByDescending { it.value }
            .take(limit)
            .map { (pkg, ms) ->
                mapOf(
                    "package" to pkg,
                    "label" to TodayUsage.label(context, pkg),
                    "minutes" to TodayUsage.toMin(ms),
                    "icon" to TodayUsage.iconPng(context, pkg),
                )
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
