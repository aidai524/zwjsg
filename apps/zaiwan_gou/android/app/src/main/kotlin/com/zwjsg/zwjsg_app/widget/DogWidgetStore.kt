package com.zwjsg.zwjsg_app.widget

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * App 和桌面小组件共用的存储（小组件和 App 是同一个进程、同一个包）：
 * - SharedPreferences `home_widget`：App 交过来的配置。狗度阈值和文案（照搬 dog_meter.dart）、每日目标、数据来源；
 * - `files/widget_avatars/`：App 预先画好的 6 张形象图（变狗阶段 0–5，见 Flutter 的 HomeWidgetSync）。
 * 只有狗度和阶段，没有任何 App 名称，也不上传。
 */
object DogWidgetStore {
    private const val PREFS = "home_widget"
    private const val KEY_CONFIG = "config"

    /** Flutter 的 DogWidgetConfig.toMap */
    data class Config(
        /** 同意了隐私政策、做完了引导 */
        val ready: Boolean,
        /** usage（按分钟算）/ screenTime（iOS 才有）/ none（还拿不到真实数据） */
        val source: String,
        val goalMinutes: Int,
        /** 阶段 1–5 的狗度阈值（百分比） */
        val thresholds: List<Int>,
        val stageNames: List<String>,
        val quips: List<String>,
        val nextChange: List<String>,
    )

    fun avatarDir(context: Context) = File(context.filesDir, "widget_avatars")

    fun saveConfig(context: Context, args: Map<*, *>?) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
        if (args == null) prefs.remove(KEY_CONFIG) else prefs.putString(KEY_CONFIG, JSONObject(args).toString())
        prefs.apply()
    }

    fun loadConfig(context: Context): Config? {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_CONFIG, null) ?: return null
        return try {
            val j = JSONObject(raw)
            Config(
                ready = j.getBoolean("ready"),
                source = j.getString("source"),
                goalMinutes = j.getInt("goal_minutes"),
                thresholds = j.getJSONArray("thresholds").ints(),
                stageNames = j.getJSONArray("stage_names").strings(),
                quips = j.getJSONArray("quips").strings(),
                nextChange = j.getJSONArray("next_change").strings(),
            )
        } catch (e: Exception) {
            null
        }
    }

    private fun JSONArray.ints() = (0 until length()).map { getInt(it) }

    private fun JSONArray.strings() = (0 until length()).map { getString(it) }
}
