package com.zwjsg.zwjsg_app

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID

/**
 * 一个单个 App 限时：这些 app 每天合计用满 [minutes] 分钟，狗版的你就打“电话”来问还玩不玩；拒接就今天锁死。
 * 按狗度来的（[dogPercent] 不为空，2026-11-27）：今天一共刷到目标的这么多（%）以后，打开这些 app 就来电，不看 [minutes]
 */
data class AppLock(val id: String, val packages: List<String>, val minutes: Int, val dogPercent: Int? = null)

/** 限时存在 App 自己的 SharedPreferences 里：只在手机上，不上传。无障碍服务和 Flutter 都从这里读 */
class LockStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences("zwjsg_locks", Context.MODE_PRIVATE)

    fun all(): List<AppLock> {
        val json = prefs.getString(KEY, null) ?: return emptyList()
        return try {
            val array = JSONArray(json)
            (0 until array.length()).map { i ->
                val o = array.getJSONObject(i)
                val packages = o.getJSONArray("packages")
                AppLock(
                    id = o.getString("id"),
                    packages = (0 until packages.length()).map { packages.getString(it) },
                    minutes = o.getInt("minutes"),
                    dogPercent = if (o.has("dogPercent")) o.getInt("dogPercent") else null,
                )
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    fun save(lock: AppLock) {
        val locks = all().filter { it.id != lock.id } + lock
        write(locks)
    }

    fun delete(id: String) {
        write(all().filter { it.id != id })
        prefs.edit().remove(graceDayKey(id)).remove(graceBaseKey(id)).remove(declinedKey(id)).apply()
    }

    // 再玩一会儿：接了“电话”、学会两声狗叫（或者没麦克风时按住 10 秒）就放行，再用满 SNOOZE_MINUTES 又来电。不限次数（按使用时长算，和 iOS 一致）

    private fun graceDayKey(id: String) = "grace.$id.day"

    /** 放行那一刻这个限时已经用了多少毫秒；再用满 SNOOZE_MINUTES 就再来电 */
    private fun graceBaseKey(id: String) = "grace.$id.base"

    private fun today() = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())

    /** 还能再玩多少毫秒；没在“再玩”中为 0 */
    fun graceRemainingMs(id: String, usedMs: Long): Long {
        if (prefs.getString(graceDayKey(id), null) != today()) return 0L
        val base = prefs.getLong(graceBaseKey(id), -1L)
        if (base < 0) return 0L
        return (base + SNOOZE_MINUTES * 60_000L - usedMs).coerceAtLeast(0L)
    }

    /** 再玩 SNOOZE_MINUTES 分钟，[usedMs] 是这个限时今天已经用了多久 */
    fun snooze(id: String, usedMs: Long) {
        prefs.edit().putString(graceDayKey(id), today()).putLong(graceBaseKey(id), usedMs).apply()
    }

    // 拒接（2026-11-23）：这个限时今天锁死，明天 0 点解开。今天再打开这些 App 直接是“今天锁死了”，不再来电

    private fun declinedKey(id: String) = "declined.$id"

    fun isDeclinedToday(id: String) = prefs.getString(declinedKey(id), null) == today()

    fun declineToday(id: String) {
        prefs.edit().putString(declinedKey(id), today()).remove(graceDayKey(id)).remove(graceBaseKey(id)).apply()
    }

    /** 每天的目标（分钟），按狗度来的限时用。Flutter 在保存这种限时、换目标时交过来；没交过是 0 */
    var goalMinutes: Int
        get() = prefs.getInt(GOAL_KEY, 0)
        set(value) = prefs.edit().putInt(GOAL_KEY, value).apply()

    /**
     * 这个限时今天还差多少毫秒到点（到了或者超了是 0 或负数）。
     * 按额度：这些 app 合计用了多久；按狗度：今天一共刷了多久（和狗度一样，不算自己和桌面）。
     * 按狗度来、但还不知道目标时为 null：不来电
     */
    fun leftMs(lock: AppLock, today: TodayUsage): Long? {
        val pct = lock.dogPercent ?: return lock.minutes * 60_000L - usedMs(lock, today)
        val goal = goalMinutes
        if (goal <= 0) return null
        return goal * pct * 600L - today.foregroundMs.values.sum()
    }

    private fun write(locks: List<AppLock>) {
        val array = JSONArray()
        locks.forEach { lock ->
            array.put(JSONObject().apply {
                put("id", lock.id)
                put("packages", JSONArray(lock.packages))
                put("minutes", lock.minutes)
                lock.dogPercent?.let { put("dogPercent", it) }
            })
        }
        prefs.edit().putString(KEY, array.toString()).apply()
    }

    companion object {
        private const val KEY = "locks"
        private const val GOAL_KEY = "goal_minutes"
        const val MAX = 10
        const val SNOOZE_MINUTES = 10

        /** 这个限时里的 app 今天合计用了多少毫秒 */
        fun usedMs(lock: AppLock, today: TodayUsage) = lock.packages.sumOf { today.foregroundMs[it] ?: 0L }

        fun newId() = UUID.randomUUID().toString().take(8)
    }
}
