package com.zwjsg.shenme_tianqi.widget

import android.content.Context
import org.json.JSONObject
import java.io.File

/**
 * App 和桌面小组件共用的存储（小组件和 App 是同一个进程、同一个包）：
 * - SharedPreferences `home_widget`：App 写的配置（查哪个城市、什么温度单位、后端地址），小组件上一次取到的天气；
 * - `files/avatars/`：App 预先画好的 61 张形象图（见 Flutter 的 HomeWidgetSync），小组件按后端给的衣服档和天气状态挑一张。
 */
object WidgetStore {
    private const val PREFS = "home_widget"
    private const val KEY_CONFIG = "config"
    private const val KEY_LAST = "last"
    private const val KEY_LAST_AT = "last_at"

    data class Config(val apiBase: String, val locationId: String, val city: String, val adm: String?, val unit: String)

    fun avatarDir(context: Context) = File(context.filesDir, "avatars")

    /** App 传来的配置（Flutter 的 HomeWidgetConfig.toMap）；null 表示还没选城市或还没同意隐私政策，连同旧天气一起删掉 */
    fun saveConfig(context: Context, args: Map<*, *>?) {
        val apiBase = args?.get("api_base") as? String
        val locationId = args?.get("location_id") as? String
        val city = args?.get("city") as? String
        val unit = args?.get("unit") as? String
        val edit = prefs(context).edit()
        if (apiBase == null || locationId == null || city == null || unit == null) {
            edit.remove(KEY_CONFIG).remove(KEY_LAST).remove(KEY_LAST_AT).apply()
            return
        }
        val json = JSONObject()
            .put("api_base", apiBase)
            .put("location_id", locationId)
            .put("city", city)
            .put("adm", args?.get("adm") as? String ?: JSONObject.NULL)
            .put("unit", unit)
        edit.putString(KEY_CONFIG, json.toString()).apply()
    }

    fun loadConfig(context: Context): Config? {
        val raw = prefs(context).getString(KEY_CONFIG, null) ?: return null
        return try {
            val j = JSONObject(raw)
            Config(
                apiBase = j.getString("api_base"),
                locationId = j.getString("location_id"),
                city = j.getString("city"),
                adm = if (j.isNull("adm")) null else j.getString("adm"),
                unit = j.getString("unit"),
            )
        } catch (e: Exception) {
            null
        }
    }

    /** 上一次取到的天气（后端返回的原文），取不到新的时先显示它 */
    fun saveLast(context: Context, body: String) {
        prefs(context).edit().putString(KEY_LAST, body).putLong(KEY_LAST_AT, System.currentTimeMillis()).apply()
    }

    fun loadLast(context: Context): Pair<String, Long>? {
        val p = prefs(context)
        val body = p.getString(KEY_LAST, null) ?: return null
        return body to p.getLong(KEY_LAST_AT, 0)
    }

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
