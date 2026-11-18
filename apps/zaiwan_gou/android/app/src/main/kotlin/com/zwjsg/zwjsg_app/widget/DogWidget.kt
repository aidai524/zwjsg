package com.zwjsg.zwjsg_app.widget

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.view.View
import android.widget.RemoteViews
import com.zwjsg.zwjsg_app.R
import com.zwjsg.zwjsg_app.TodayUsage
import java.io.File
import java.util.Calendar
import java.util.concurrent.Executors
import kotlin.math.ceil
import kotlin.math.roundToInt

// 再玩我是狗的桌面小组件：不打开 App 也能看到现在的形象和狗度（需求文档 P1）。
// 小组件自己用 TodayUsage 算今天刷了多久（和 App 的狗度同一个算法，要“使用情况访问权限”），
// 系统大约每 30 分钟叫醒一次；0 点另有闹钟让它变回人。规则和文案都是 App 交过来的（照搬 dog_meter.dart）。
// 只在手机上算、只显示狗度和阶段，不显示任何 App 名称，也不上传。和 iOS 的 GouWidget.swift 对应。

/** 小号（2×2）：狗度、形象、阶段牌、一句吐槽 */
class SmallDogWidget : DogWidgetProvider(R.layout.widget_dog_small, small = true)

/** 中号（4×2）：形象 + 狗度、阶段牌、吐槽、今日已刷、再刷多久会变成什么样 */
class MediumDogWidget : DogWidgetProvider(R.layout.widget_dog_medium, small = false)

/** 小组件上显示的东西 */
data class DogView(
    val stage: Int,
    val percent: String,
    val stageName: String,
    val quip: String,
    /** “今日已刷 2 小时 10 分 · 目标 3 小时” */
    val used: String,
    /** “再刷 25 分钟，你就会脸上长毛” */
    val hint: String,
)

sealed class DogContent {
    data class Dog(val view: DogView) : DogContent()

    /** 还没做完设置、还没开权限 */
    data class Message(val text: String) : DogContent()
}

object DogLoader {
    private const val SETUP = "打开 App 做完设置，这里就能看到你今天有多像狗"
    private const val PERMISSION = "打开 App 开启“使用情况访问权限”，这里就能看到狗度"

    fun load(context: Context): DogContent {
        val c = DogWidgetStore.loadConfig(context) ?: return DogContent.Message(SETUP)
        val n = c.thresholds.size
        if (!c.ready || n == 0 || c.stageNames.size != n + 1 || c.quips.size != n + 1 || c.nextChange.size != n) {
            return DogContent.Message(SETUP)
        }
        // 权限可能在系统设置里被关掉了
        if (c.source != "usage" || !TodayUsage.hasPermission(context)) return DogContent.Message(PERMISSION)
        val minutes = TodayUsage.toMin(TodayUsage.compute(context).foregroundMs.values.sum())
        return DogContent.Dog(view(c, minutes))
    }

    /** 和 DogMeter.percentFor、stageFor、minutesToNextStage，以及“今天”页的提示一样 */
    fun view(c: DogWidgetStore.Config, minutes: Int): DogView {
        val percent = if (c.goalMinutes <= 0) 0 else (minutes * 100.0 / c.goalMinutes).roundToInt()
        val stage = c.thresholds.count { percent >= it }
        val hint = if (stage >= c.thresholds.size) {
            "已经到底了，再刷也还是狗"
        } else {
            val target = ceil(c.thresholds[stage] * c.goalMinutes / 100.0).toInt()
            "再刷 ${formatMinutes((target - minutes).coerceIn(0, 24 * 60))}，你就会${c.nextChange[stage]}"
        }
        return DogView(
            stage = stage,
            percent = "$percent%",
            stageName = c.stageNames[stage],
            quip = c.quips[stage],
            used = "今日已刷 ${formatMinutes(minutes)} · 目标 ${formatMinutes(c.goalMinutes)}",
            hint = hint,
        )
    }

    /** 和 DogMeter.formatMinutes 一样 */
    fun formatMinutes(minutes: Int): String {
        val h = minutes / 60
        val m = minutes % 60
        return when {
            h == 0 -> "$m 分钟"
            m == 0 -> "$h 小时"
            else -> "$h 小时 $m 分"
        }
    }
}

abstract class DogWidgetProvider(private val layout: Int, private val small: Boolean) : AppWidgetProvider() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_MIDNIGHT) {
            refreshAll(context)
            return
        }
        super.onReceive(context, intent)
    }

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        // 读使用记录要一点时间，放到后台线程，算完再结束这次广播
        val pending = goAsync()
        executor.execute {
            try {
                val views = render(context, DogLoader.load(context))
                for (id in ids) manager.updateAppWidget(id, views)
                scheduleMidnight(context)
            } finally {
                pending.finish()
            }
        }
    }

    private fun render(context: Context, content: DogContent): RemoteViews {
        val views = RemoteViews(context.packageName, layout)
        // 点小组件打开 App
        context.packageManager.getLaunchIntentForPackage(context.packageName)?.let { intent ->
            val pi = PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            views.setOnClickPendingIntent(R.id.widget_root, pi)
        }
        when (content) {
            is DogContent.Message -> {
                views.setViewVisibility(R.id.dog_group, View.GONE)
                views.setViewVisibility(R.id.message_group, View.VISIBLE)
                views.setTextViewText(R.id.message_text, content.text)
            }
            is DogContent.Dog -> {
                val v = content.view
                views.setViewVisibility(R.id.dog_group, View.VISIBLE)
                views.setViewVisibility(R.id.message_group, View.GONE)
                views.setTextViewText(R.id.percent, v.percent)
                views.setTextViewText(R.id.stage, v.stageName)
                views.setTextViewText(R.id.quip, v.quip)
                setAvatar(context, views, v.stage)
                // 下面这些只有中号有
                if (!small) {
                    views.setTextViewText(R.id.used, v.used)
                    views.setTextViewText(R.id.hint, v.hint)
                }
            }
        }
        return views
    }

    /** App 预先画好的形象图；还没画好时放 App 图标 */
    private fun setAvatar(context: Context, views: RemoteViews, stage: Int) {
        val file = File(DogWidgetStore.avatarDir(context), "dog_$stage.png")
        val bitmap = file.takeIf { it.exists() }?.let { BitmapFactory.decodeFile(it.path) }
        if (bitmap != null) views.setImageViewBitmap(R.id.avatar, bitmap) else views.setImageViewResource(R.id.avatar, R.mipmap.ic_launcher)
    }

    companion object {
        private const val ACTION_MIDNIGHT = "com.zwjsg.zwjsg_app.widget.MIDNIGHT"
        private val executor = Executors.newSingleThreadExecutor()

        /** 0 点过 1 分钟叫小组件重算一次，变回人。不用精确闹钟：晚几分钟没关系，也不用申请权限 */
        private fun scheduleMidnight(context: Context) {
            val next = Calendar.getInstance().apply {
                add(Calendar.DAY_OF_YEAR, 1)
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 1)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }.timeInMillis
            val intent = Intent(context, SmallDogWidget::class.java).setAction(ACTION_MIDNIGHT)
            val pi = PendingIntent.getBroadcast(context, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            (context.getSystemService(Context.ALARM_SERVICE) as AlarmManager).set(AlarmManager.RTC, next, pi)
        }

        /** App 那边配置、形象图、狗度变了：让所有小组件马上重算、重画 */
        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            for (cls in listOf(SmallDogWidget::class.java, MediumDogWidget::class.java)) {
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
