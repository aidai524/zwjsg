package com.zwjsg.zwjsg_app

import android.app.Activity
import android.content.Intent
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.media.AudioAttributes
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import android.speech.tts.TextToSpeech
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.animation.AlphaAnimation
import android.view.animation.Animation
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import com.zwjsg.zwjsg_app.widget.DogLoader
import com.zwjsg.zwjsg_app.widget.DogView
import com.zwjsg.zwjsg_app.widget.DogWidgetStore
import java.io.File
import java.util.Locale

/**
 * 单个 App 超时的“来电提醒”：用满每天的额度后不禁止，而是像来了个语音电话——
 * 你的狗（按今天的狗度画的那张形象）打过来，问你“还确定要玩吗？”。
 * - 响铃、震动；“挂断”就是不玩了，回桌面
 * - “接听”后它说几句（屏幕上有字；手机有中文语音时也念出来），再选“不玩了”或“再玩 10 分钟”，到点再来电，不限次数
 * App 名称只显示在这一页上；念出来的话里不带 App 名称（系统的语音引擎可能是第三方的）。不上传任何东西。
 */
class CallReminderActivity : Activity(), TextToSpeech.OnInitListener {

    companion object {
        const val EXTRA_LABEL = "label"
        const val EXTRA_LIMIT = "limit"
        const val EXTRA_USED = "used"
        const val EXTRA_LOCK_ID = "lockId"

        /** 响多久没人接就不响了（页面还在，还是得选） */
        private const val RING_MS = 30_000L

        /** 接听后一句一句出来的间隔 */
        private const val LINE_MS = 1_600L

        // 和 Flutter 那边的配色一致（pop_ui 的 Pop）；接听、挂断用通话界面常见的绿和红
        private val INK = Color.parseColor("#1B1B1F")
        private val YELLOW = Color.parseColor("#FFD23F")
        private val RED = Color.parseColor("#E5484D")
        private val GREEN = Color.parseColor("#2FB45A")
        private val FAINT = Color.argb(170, 255, 255, 255)

        fun formatMinutes(m: Int) = DogLoader.formatMinutes(m)
    }

    private val handler = Handler(Looper.getMainLooper())
    private var ringtone: Ringtone? = null
    private var vibrator: Vibrator? = null
    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var answered = false
    private var answeredAt = 0L
    private var spoken: String? = null

    private lateinit var label: String
    private var limit = 0
    private var used = 0
    private var lockId: String? = null
    private var dog: DogView? = null

    private lateinit var halo: View
    private lateinit var status: TextView
    private lateinit var bubble: TextView
    private lateinit var actions: LinearLayout

    private val dp by lazy { resources.displayMetrics.density }
    private fun px(v: Int) = (v * dp).toInt()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = INK
        window.navigationBarColor = INK
        label = intent.getStringExtra(EXTRA_LABEL) ?: "这个 App"
        limit = intent.getIntExtra(EXTRA_LIMIT, 0)
        used = intent.getIntExtra(EXTRA_USED, limit)
        lockId = intent.getStringExtra(EXTRA_LOCK_ID)
        dog = runCatching { dogNow() }.getOrNull()

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setBackgroundColor(INK)
            setPadding(px(28), px(64), px(28), px(44))
        }
        root.addView(text("再玩我是狗 · 语音来电", 13f, FAINT))
        root.addView(text("你的狗", 34f, Color.WHITE, bold = true, topDp = 10))
        dog?.let { root.addView(text(it.stageName, 15f, YELLOW, bold = true, topDp = 6)) }
        root.addView(avatar(), LinearLayout.LayoutParams(px(212), px(212)).apply { topMargin = px(28) })
        status = text("正在呼叫你…", 15f, FAINT, topDp = 22)
        root.addView(status)
        bubble = text("", 16f, INK, bold = true, topDp = 18).apply {
            gravity = Gravity.START
            setLineSpacing(0f, 1.35f)
            setPadding(px(16), px(12), px(16), px(12))
            background = GradientDrawable().apply { setColor(Color.WHITE); cornerRadius = 18 * dp }
            visibility = View.GONE
        }
        root.addView(bubble)
        root.addView(View(this), LinearLayout.LayoutParams(MATCH_PARENT, 0, 1f))
        actions = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER }
        root.addView(actions, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        showRingingActions()
        setContentView(root)

        startRinging()
        tts = TextToSpeech(this, this)
        handler.postDelayed({
            if (!answered) {
                stopRinging()
                status.text = "没接？它不会挂的，接一下吧"
            }
        }, RING_MS)
    }

    /** 今天的狗：和桌面小组件同一套算法和文案（App 交过来的） */
    private fun dogNow(): DogView? {
        val c = DogWidgetStore.loadConfig(this) ?: return null
        if (c.thresholds.isEmpty() || c.stageNames.size != c.thresholds.size + 1 || !TodayUsage.hasPermission(this)) return null
        return DogLoader.view(c, TodayUsage.toMin(TodayUsage.compute(this).foregroundMs.values.sum()))
    }

    /** 白底圆框里的形象，外面一圈黄色光环，响铃时一明一暗 */
    private fun avatar(): View {
        val frame = FrameLayout(this)
        halo = View(this).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setStroke(px(5), YELLOW)
            }
        }
        frame.addView(halo, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        val image = ImageView(this).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.WHITE)
            }
            clipToOutline = true
            scaleType = ImageView.ScaleType.FIT_END
            contentDescription = dog?.let { "你的狗，${it.stageName}" } ?: "你的狗"
            val file = File(DogWidgetStore.avatarDir(this@CallReminderActivity), "dog_${dog?.stage ?: 0}.png")
            val bitmap = file.takeIf { it.exists() }?.let { BitmapFactory.decodeFile(it.path) }
            if (bitmap != null) setImageBitmap(bitmap) else setImageResource(R.mipmap.ic_launcher)
        }
        frame.addView(image, FrameLayout.LayoutParams(px(184), px(184), Gravity.CENTER))
        halo.startAnimation(AlphaAnimation(1f, 0.2f).apply {
            duration = 700
            repeatMode = Animation.REVERSE
            repeatCount = Animation.INFINITE
        })
        return frame
    }

    private fun text(value: String, sizeSp: Float, color: Int, bold: Boolean = false, topDp: Int = 0) = TextView(this).apply {
        text = value
        textSize = sizeSp
        setTextColor(color)
        gravity = Gravity.CENTER
        if (bold) typeface = Typeface.DEFAULT_BOLD
        layoutParams = LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply { topMargin = px(topDp) }
    }

    /** 响铃时：挂断（不玩了）、接听 */
    private fun showRingingActions() {
        actions.removeAllViews()
        actions.addView(roundButton("挂断", "挂断，不玩了", RED) { goHome() }, weight())
        actions.addView(roundButton("接听", "接听", GREEN) { answer() }, weight())
    }

    private fun weight() = LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f)

    private fun roundButton(caption: String, description: String, color: Int, onTap: () -> Unit) =
        LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            val circle = TextView(this@CallReminderActivity).apply {
                text = caption
                textSize = 17f
                setTextColor(Color.WHITE)
                typeface = Typeface.DEFAULT_BOLD
                gravity = Gravity.CENTER
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(color)
                }
                contentDescription = description
                isClickable = true
                setOnClickListener { onTap() }
            }
            addView(circle, LinearLayout.LayoutParams(px(76), px(76)))
        }

    private fun pillButton(caption: String, filled: Boolean, onTap: () -> Unit) = TextView(this).apply {
        text = caption
        textSize = 17f
        typeface = Typeface.DEFAULT_BOLD
        gravity = Gravity.CENTER
        setTextColor(if (filled) INK else Color.WHITE)
        background = GradientDrawable().apply {
            cornerRadius = 28 * dp
            if (filled) setColor(YELLOW) else setStroke(px(2), Color.WHITE)
        }
        isClickable = true
        setOnClickListener { onTap() }
        layoutParams = LinearLayout.LayoutParams(MATCH_PARENT, px(54)).apply { topMargin = px(12) }
    }

    private fun answer() {
        if (answered) return
        answered = true
        answeredAt = SystemClock.elapsedRealtime()
        stopRinging()
        halo.clearAnimation()
        tick()
        val quip = dog?.quip ?: "再刷下去，我就要完全变成狗了"
        val lines = listOf(
            "喂？是我，你的狗。",
            "「$label」今天已经刷了 ${formatMinutes(used)}，说好一天 ${formatMinutes(limit)}。",
            "$quip。",
            "你还确定要玩吗？",
        )
        bubble.visibility = View.VISIBLE
        lines.forEachIndexed { i, line ->
            handler.postDelayed({ bubble.text = lines.take(i + 1).joinToString("\n") }, i * LINE_MS)
        }
        // 念出来的不带 App 名称：系统的语音引擎可能是第三方的
        spoken = "喂？是我，你的狗。你今天的时间已经用完了。$quip。你还确定要玩吗？"
        speak()

        actions.removeAllViews()
        actions.orientation = LinearLayout.VERTICAL
        actions.addView(pillButton("不玩了", filled = true) { goHome() })
        actions.addView(pillButton("再玩 ${LockStore.SNOOZE_MINUTES} 分钟", filled = false) { snooze() })
    }

    /** 通话时长 */
    private fun tick() {
        val s = ((SystemClock.elapsedRealtime() - answeredAt) / 1000).toInt()
        status.text = String.format(Locale.US, "通话中 %02d:%02d", s / 60, s % 60)
        handler.postDelayed({ if (!isFinishing) tick() }, 1000)
    }

    override fun onInit(status: Int) {
        if (status != TextToSpeech.SUCCESS) return
        val lang = tts?.setLanguage(Locale.SIMPLIFIED_CHINESE) ?: TextToSpeech.LANG_NOT_SUPPORTED
        ttsReady = lang >= TextToSpeech.LANG_AVAILABLE
        tts?.setPitch(1.15f)
        if (answered) speak()
    }

    private fun speak() {
        val words = spoken ?: return
        if (!ttsReady) return
        tts?.speak(words, TextToSpeech.QUEUE_FLUSH, null, "dog_call")
    }

    private fun startRinging() {
        ringtone = runCatching {
            RingtoneManager.getRingtone(this, RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE))
        }.getOrNull()?.apply {
            audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) isLooping = true
            play()
        }
        vibrator = (getSystemService(VIBRATOR_SERVICE) as? Vibrator)?.takeIf { it.hasVibrator() }?.apply {
            val pattern = longArrayOf(0, 800, 700)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrate(VibrationEffect.createWaveform(pattern, 0))
            } else {
                @Suppress("DEPRECATION")
                vibrate(pattern, 0)
            }
        }
    }

    private fun stopRinging() {
        ringtone?.stop()
        ringtone = null
        vibrator?.cancel()
        vibrator = null
    }

    /** 再玩 10 分钟：放行，回到那个 App；再用满 10 分钟，无障碍服务会再来电 */
    private fun snooze() {
        val id = lockId
        val store = LockStore(this)
        val lock = store.all().firstOrNull { it.id == id }
        if (lock != null) {
            val usedMs = if (TodayUsage.hasPermission(this)) LockStore.usedMs(lock, TodayUsage.compute(this)) else used * 60_000L
            store.snooze(lock.id, usedMs)
        }
        finish()
    }

    @Suppress("OVERRIDE_DEPRECATION")
    override fun onBackPressed() = goHome()

    /** 不玩了：回桌面 */
    private fun goHome() {
        startActivity(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        finish()
    }

    override fun onStop() {
        super.onStop()
        // 切走了就别一直响
        stopRinging()
        tts?.stop()
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        stopRinging()
        tts?.shutdown()
        super.onDestroy()
    }
}
