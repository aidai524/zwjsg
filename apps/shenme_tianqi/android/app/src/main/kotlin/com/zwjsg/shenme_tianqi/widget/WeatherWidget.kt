package com.zwjsg.shenme_tianqi.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import com.zwjsg.shenme_tianqi.R
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

// 什么鬼天气的桌面小组件：常驻城市的温度、形象和一句话结论（小号：伞、秋裤两张决策卡；中号：一句话 + 四张决策卡）。
// 系统大约每 30 分钟叫醒一次（updatePeriodMillis），小组件自己向后端取精简天气（GET /widget/{locationId}），
// 温度和句子后端按单位写好了，这里原样显示；结论全部是后端算的，这里不做判断。
// 严肃模式（黄色及以上预警）只显示预警标题原文、发布单位和时间，不显示决策卡。和 iOS 的 WeatherWidget.swift 对应。

/** 小号（2×2）：城市、天气、温度；形象；伞和秋裤 */
class SmallWeatherWidget : WeatherWidgetProvider(R.layout.widget_small, small = true)

/** 中号（4×2）：形象 + 城市和实况时间、温度、一句话结论、四张决策卡 */
class MediumWeatherWidget : WeatherWidgetProvider(R.layout.widget_medium, small = false)

/** 后端 GET /widget/{locationId} 返回的精简天气 */
data class WidgetWeather(
    val locationId: String,
    val unit: String,
    val temp: String,
    val text: String,
    val range: String?,
    val cond: String,
    val outfit: String,
    val serious: Boolean,
    val line: String?,
    val decisions: List<Decision>,
    val warning: Warning?,
    val warningsCount: Int,
    val obsTime: String?,
    val credit: String,
) {
    data class Decision(val title: String, val label: String, val action: Boolean)
    data class Warning(val title: String, val sender: String, val pubTime: String, val color: String)

    companion object {
        private fun JSONObject.str(key: String): String? = if (isNull(key)) null else optString(key)

        fun parse(j: JSONObject): WidgetWeather {
            val ds = j.getJSONArray("decisions")
            val w = j.optJSONObject("warning")
            return WidgetWeather(
                locationId = j.getString("location_id"),
                unit = j.getString("unit"),
                temp = j.getString("temp"),
                text = j.getString("text"),
                range = j.str("range"),
                cond = j.getString("cond"),
                outfit = j.getString("outfit"),
                serious = j.getBoolean("serious"),
                line = j.str("line"),
                decisions = (0 until ds.length()).map { i ->
                    val d = ds.getJSONObject(i)
                    Decision(d.getString("title"), d.getString("label"), d.getBoolean("action"))
                },
                warning = w?.let { Warning(it.getString("title"), it.getString("sender"), it.getString("pub_time"), it.getString("color")) },
                warningsCount = j.optInt("warnings_count"),
                obsTime = j.str("obs_time"),
                credit = j.optString("credit", "天气服务由和风天气驱动"),
            )
        }
    }
}

sealed class WidgetContent {
    data class Weather(val city: String, val weather: WidgetWeather) : WidgetContent()

    /** 还没在 App 里选城市 */
    object Setup : WidgetContent()

    /** 取不到天气，也没有能用的旧数据 */
    data class Unavailable(val city: String) : WidgetContent()
}

object WeatherLoader {
    /** 旧数据最多显示 3 小时，再久就说取不到，免得把过时的天气当成现在的 */
    private const val MAX_STALE_MS = 3 * 3600 * 1000L

    fun load(context: Context): WidgetContent {
        val config = WidgetStore.loadConfig(context) ?: return WidgetContent.Setup
        fetch(config)?.let { (weather, body) ->
            WidgetStore.saveLast(context, body)
            return WidgetContent.Weather(config.city, weather)
        }
        cached(context, config)?.let { return WidgetContent.Weather(config.city, it) }
        return WidgetContent.Unavailable(config.city)
    }

    private fun fetch(config: WidgetStore.Config): Pair<WidgetWeather, String>? {
        val url = Uri.parse("${config.apiBase}/widget/${config.locationId}").buildUpon()
            .appendQueryParameter("unit", config.unit)
            .apply { config.adm?.let { appendQueryParameter("adm", it) } }
            .build().toString()
        var conn: HttpURLConnection? = null
        return try {
            conn = (URL(url).openConnection() as HttpURLConnection).apply {
                connectTimeout = 15_000
                readTimeout = 15_000
                setRequestProperty("Accept", "application/json")
            }
            if (conn.responseCode != 200) return null
            val body = conn.inputStream.bufferedReader().use { it.readText() }
            WidgetWeather.parse(JSONObject(body).getJSONObject("data")) to body
        } catch (e: Exception) {
            null
        } finally {
            conn?.disconnect()
        }
    }

    /** 同一个城市、同一个单位、3 小时内的旧数据才用 */
    private fun cached(context: Context, config: WidgetStore.Config): WidgetWeather? {
        val (body, at) = WidgetStore.loadLast(context) ?: return null
        if (System.currentTimeMillis() - at > MAX_STALE_MS) return null
        val weather = try {
            WidgetWeather.parse(JSONObject(body).getJSONObject("data"))
        } catch (e: Exception) {
            return null
        }
        return weather.takeIf { it.locationId == config.locationId && it.unit == config.unit }
    }
}

abstract class WeatherWidgetProvider(private val layout: Int, private val small: Boolean) : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        // 联网不能在主线程：交给后台线程，取完再结束这次广播
        val pending = goAsync()
        executor.execute {
            try {
                val views = render(context, WeatherLoader.load(context))
                for (id in ids) manager.updateAppWidget(id, views)
            } finally {
                pending.finish()
            }
        }
    }

    private fun render(context: Context, content: WidgetContent): RemoteViews {
        val views = RemoteViews(context.packageName, layout)
        // 点小组件打开 App
        context.packageManager.getLaunchIntentForPackage(context.packageName)?.let { intent ->
            val pi = PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            views.setOnClickPendingIntent(R.id.widget_root, pi)
        }
        when (content) {
            is WidgetContent.Setup -> message(views, "什么鬼天气", "打开 App 选个城市，这里就有天气了")
            is WidgetContent.Unavailable -> message(views, content.city, "天气暂时拿不到，过会儿再看")
            is WidgetContent.Weather ->
                if (content.weather.serious) serious(context, views, content.city, content.weather)
                else weather(context, views, content.city, content.weather)
        }
        return views
    }

    private fun show(views: RemoteViews, group: Int) {
        for (id in listOf(R.id.weather_group, R.id.serious_group, R.id.message_group)) {
            views.setViewVisibility(id, if (id == group) View.VISIBLE else View.GONE)
        }
    }

    private fun message(views: RemoteViews, title: String, text: String) {
        show(views, R.id.message_group)
        views.setInt(R.id.widget_root, "setBackgroundResource", R.drawable.widget_background)
        views.setTextViewText(R.id.message_title, title)
        views.setTextViewText(R.id.message_text, text)
    }

    private fun weather(context: Context, views: RemoteViews, city: String, w: WidgetWeather) {
        show(views, R.id.weather_group)
        views.setInt(R.id.widget_root, "setBackgroundResource", R.drawable.widget_background)
        views.setTextViewText(R.id.city, city)
        views.setTextViewText(R.id.text, w.text)
        views.setTextViewText(R.id.temp, w.temp)
        setAvatar(context, views, R.id.avatar, w)

        val chips = if (small) listOf(R.id.chip0, R.id.chip1) else listOf(R.id.chip0, R.id.chip1, R.id.chip2, R.id.chip3)
        chips.forEachIndexed { i, id ->
            val d = w.decisions.getOrNull(i)
            if (d == null) {
                views.setViewVisibility(id, View.INVISIBLE)
                return@forEachIndexed
            }
            views.setViewVisibility(id, View.VISIBLE)
            views.setTextViewText(id, "${d.title} ${d.label}")
            views.setTextColor(id, if (d.action) YELLOW else INK)
            views.setInt(id, "setBackgroundResource", if (d.action) R.drawable.widget_chip_action else R.drawable.widget_chip)
        }

        // 下面这些只有中号有
        if (small) return
        views.setTextViewText(R.id.obs, hm(w.obsTime)?.let { "$it 实况" } ?: "")
        views.setTextViewText(R.id.range, w.range ?: "")
        views.setTextViewText(R.id.line, w.line ?: "")
    }

    private fun serious(context: Context, views: RemoteViews, city: String, w: WidgetWeather) {
        show(views, R.id.serious_group)
        views.setInt(R.id.widget_root, "setBackgroundResource", R.drawable.widget_background_serious)
        views.setTextViewText(R.id.serious_city, city)
        views.setTextViewText(R.id.serious_temp, w.temp)
        val warning = w.warning
        if (warning != null) {
            views.setViewVisibility(R.id.warning_title, View.VISIBLE)
            views.setTextViewText(R.id.warning_title, warning.title)
            val (bg, onDark) = warningStyle(warning.color)
            views.setInt(R.id.warning_title, "setBackgroundResource", bg)
            views.setTextColor(R.id.warning_title, if (onDark) WHITE else INK)
            views.setTextViewText(R.id.warning_source, "${warning.sender} ${mdhm(warning.pubTime)} 发布")
        } else {
            views.setViewVisibility(R.id.warning_title, View.GONE)
            views.setTextViewText(R.id.warning_source, "")
        }
        views.setTextViewText(R.id.warning_hint, if (w.warningsCount > 1) "共 ${w.warningsCount} 条预警，点开看原文" else "点开看预警原文")
        if (!small) setAvatar(context, views, R.id.serious_avatar, w)
    }

    /** App 预先画好的形象图；还没画好时放 App 图标 */
    private fun setAvatar(context: Context, views: RemoteViews, id: Int, w: WidgetWeather) {
        val name = if (w.cond == "serious") "avatar_serious.png" else "avatar_${w.outfit}_${w.cond}.png"
        val bitmap = File(WidgetStore.avatarDir(context), name).takeIf { it.exists() }?.let { BitmapFactory.decodeFile(it.path) }
        if (bitmap != null) views.setImageViewBitmap(id, bitmap) else views.setImageViewResource(id, R.mipmap.ic_launcher)
    }

    companion object {
        private val executor = Executors.newSingleThreadExecutor()

        // 和 res/values/colors.xml、pop_ui 的 Pop 颜色一致
        private const val INK = 0xFF1B1B1F.toInt()
        private const val YELLOW = 0xFFFFD23F.toInt()
        private const val WHITE = 0xFFFFFFFF.toInt()

        /** 预警颜色，和 App 的 scene.dart 里 warningColor、onWarningColor 一致：返回（底色，是不是深底白字） */
        private fun warningStyle(color: String): Pair<Int, Boolean> = when (color) {
            "Red" -> R.drawable.widget_warning_red to true
            "Orange" -> R.drawable.widget_warning_orange to false
            "Yellow" -> R.drawable.widget_warning_yellow to false
            "Blue" -> R.drawable.widget_warning_blue to true
            "Black" -> R.drawable.widget_warning_black to true
            else -> R.drawable.widget_warning_other to false
        }

        /** "2026-11-06T08:00+08:00" → "08:00"（城市当地时间，原样取） */
        private fun hm(iso: String?): String? {
            if (iso == null) return null
            val t = iso.indexOf('T')
            return if (t < 0 || iso.length < t + 6) null else iso.substring(t + 1, t + 6)
        }

        /** "2026-11-06T07:00+08:00" → "11-06 07:00" */
        private fun mdhm(iso: String): String = if (iso.length >= 10) "${iso.substring(5, 10)} ${hm(iso) ?: ""}" else iso

        /** App 那边城市、单位、形象图变了：让所有小组件马上重新取天气、重画 */
        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            for (cls in listOf(SmallWeatherWidget::class.java, MediumWeatherWidget::class.java)) {
                val ids = manager.getAppWidgetIds(ComponentName(context, cls))
                if (ids.isEmpty()) continue
                context.sendBroadcast(
                    Intent(context, cls)
                        .setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE)
                        .putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids),
                )
            }
        }
    }
}
