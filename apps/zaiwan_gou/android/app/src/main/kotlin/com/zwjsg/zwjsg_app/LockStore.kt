package com.zwjsg.zwjsg_app

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID

/** 一个 App 时间锁：这些 app 每天合计用满 [minutes] 分钟，就拦到 0 点 */
data class AppLock(val id: String, val packages: List<String>, val minutes: Int)

/** 时间锁存在 App 自己的 SharedPreferences 里：只在手机上，不上传。无障碍服务和 Flutter 都从这里读 */
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
        prefs.edit().remove(graceDayKey(id)).remove(graceCountKey(id)).remove(graceBaseKey(id)).apply()
    }

    // 紧急解锁：每个锁每天 GRACES_PER_DAY 次，每次再用 GRACE_MINUTES 分钟（按使用时长算，和 iOS 一致）

    private fun graceDayKey(id: String) = "grace.$id.day"
    private fun graceCountKey(id: String) = "grace.$id.count"

    /** 解锁那一刻这个锁已经用了多少毫秒；再用满 GRACE_MINUTES 就重新拦 */
    private fun graceBaseKey(id: String) = "grace.$id.base"

    private fun today() = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())

    private fun usedGracesToday(id: String) =
        if (prefs.getString(graceDayKey(id), null) == today()) prefs.getInt(graceCountKey(id), 0) else 0

    /** 今天还能紧急解锁几次 */
    fun graceLeft(id: String) = (GRACES_PER_DAY - usedGracesToday(id)).coerceAtLeast(0)

    /** 临时解锁还剩多少毫秒可用；没在临时解锁中为 0 */
    fun graceRemainingMs(id: String, usedMs: Long): Long {
        if (usedGracesToday(id) == 0) return 0L
        val base = prefs.getLong(graceBaseKey(id), -1L)
        if (base < 0) return 0L
        return (base + GRACE_MINUTES * 60_000L - usedMs).coerceAtLeast(0L)
    }

    /** 用掉一次紧急解锁，[usedMs] 是这个锁今天已经用了多久；次数用完返回 false */
    fun grantGrace(id: String, usedMs: Long): Boolean {
        val used = usedGracesToday(id)
        if (used >= GRACES_PER_DAY) return false
        prefs.edit()
            .putString(graceDayKey(id), today())
            .putInt(graceCountKey(id), used + 1)
            .putLong(graceBaseKey(id), usedMs)
            .apply()
        return true
    }

    private fun write(locks: List<AppLock>) {
        val array = JSONArray()
        locks.forEach { lock ->
            array.put(JSONObject().apply {
                put("id", lock.id)
                put("packages", JSONArray(lock.packages))
                put("minutes", lock.minutes)
            })
        }
        prefs.edit().putString(KEY, array.toString()).apply()
    }

    companion object {
        private const val KEY = "locks"
        const val MAX = 10
        const val GRACES_PER_DAY = 3
        const val GRACE_MINUTES = 5

        /** 这个锁里的 app 今天合计用了多少毫秒 */
        fun usedMs(lock: AppLock, today: TodayUsage) = lock.packages.sumOf { today.foregroundMs[it] ?: 0L }

        fun newId() = UUID.randomUUID().toString().take(8)
    }
}
