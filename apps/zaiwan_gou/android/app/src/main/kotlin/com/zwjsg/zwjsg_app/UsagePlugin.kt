package com.zwjsg.zwjsg_app

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.text.SimpleDateFormat
import java.util.Locale

/**
 * 读取当天的手机使用情况。
 * 隐私约定：getTodayUsage 给狗度和上报用，只有分类汇总，不含任何 app 名称；
 * getTodayRanking / getRanking 把各 app 的名称、图标和用时交给 Flutter，只在手机上显示排行，绝不上传。
 * getPastDays 给历史统计补上前几天（没打开 App 的日子）的汇总，同样只有分类汇总。
 */
class UsagePlugin(private val context: Context) {
    companion object {
        /** 系统一般只留 7–10 天的明细，多要也没有 */
        private const val MAX_DAYS = 14
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "zwjsg/usage").setMethodCallHandler { call, result ->
            when (call.method) {
                // 要读每个 app 的名称和图标、逐天算记录，都放到后台线程，结果回主线程
                "getTodayRanking" -> inBackground(result) { ranking(days = 1) }
                "getRanking" -> {
                    val days = (call.argument<Int>("days") ?: 7).coerceIn(1, MAX_DAYS)
                    inBackground(result) { ranking(days) }
                }
                "getPastDays" -> {
                    val days = (call.argument<Int>("days") ?: 7).coerceIn(1, MAX_DAYS)
                    inBackground(result) { pastDays(days) }
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

    private fun inBackground(result: MethodChannel.Result, work: () -> Any) {
        if (!TodayUsage.hasPermission(context)) {
            result.error("NO_PERMISSION", "未授权使用情况访问权限", null)
            return
        }
        Thread {
            val value = runCatching(work)
            mainHandler.post {
                value.fold({ result.success(it) }, { result.error("USAGE_FAILED", it.message, null) })
            }
        }.start()
    }

    private fun todayUsage(): Map<String, Any> = summary(TodayUsage.compute(context))

    /** 只有分类汇总，不含 app 名称 */
    private fun summary(usage: TodayUsage): Map<String, Any> {
        val categoryMs = HashMap<String, Long>()
        for ((pkg, ms) in usage.foregroundMs) {
            val cat = categoryOf(pkg)
            categoryMs[cat] = (categoryMs[cat] ?: 0L) + ms
        }
        return mapOf(
            "totalMinutes" to TodayUsage.toMin(usage.foregroundMs.values.sum()),
            "pickups" to usage.pickups,
            "lateNightMinutes" to TodayUsage.toMin(usage.lateNightMs),
            "categoryMinutes" to categoryMs.mapValues { TodayUsage.toMin(it.value) },
        )
    }

    /** 昨天往前 [days] 天，每天一条汇总；系统已经没有记录的日子不返回（不当成那天没用手机） */
    private fun pastDays(days: Int): List<Map<String, Any>> {
        val format = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        return (1..days).mapNotNull { ago ->
            TodayUsage.computeDay(context, ago)?.let { summary(it) + ("date" to format.format(TodayUsage.dayStart(ago))) }
        }
    }

    /** 最近 [days] 天（含今天）用时最多的前 [limit] 个 app，不到 1 分钟的不算 */
    private fun ranking(days: Int, limit: Int = 30): List<Map<String, Any?>> {
        val total = HashMap(TodayUsage.compute(context).foregroundMs)
        for (ago in 1 until days) {
            TodayUsage.computeDay(context, ago)?.foregroundMs?.forEach { (pkg, ms) -> total[pkg] = (total[pkg] ?: 0L) + ms }
        }
        return total.entries
            .filter { it.value >= 60_000L }
            .sortedByDescending { it.value }
            .take(limit)
            .map { (pkg, ms) ->
                mapOf(
                    "package" to pkg,
                    "label" to TodayUsage.label(context, pkg),
                    "minutes" to TodayUsage.toMin(ms),
                    "icon" to TodayUsage.iconPng(context, pkg),
                    // 超时来电的建议要看是不是娱乐类（很多国内 App 不标分类，是 other）
                    "category" to categoryOf(pkg),
                )
            }
    }

    private fun categoryOf(pkg: String): String = TodayUsage.categoryOf(context, pkg)
}
