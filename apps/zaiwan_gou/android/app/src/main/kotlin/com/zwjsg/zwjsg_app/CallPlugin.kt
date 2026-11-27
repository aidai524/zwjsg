package com.zwjsg.zwjsg_app

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.provider.Settings
import android.speech.tts.TextToSpeech
import io.flutter.FlutterInjector
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.Locale
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.sqrt

/**
 * 来电界面（Flutter 的 CallScreen）要的原生能力，在 [CallReminderActivity] 的引擎里注册；
 * 主界面（MainActivity）也注册一份，给“试一下来电”响铃、说话、听狗叫（那边没有来电信息，也不会关掉主界面）。
 * 来电信息、响铃和震动（手机自己的来电铃声，静音、震动模式下跟系统来电一样）、接通和挂断的提示音、
 * 狗版的你说话（放打包好的语音，放不了才用系统语音，念的话里不带 App 名称）、听狗叫（每 20 毫秒的音量，
 * 加上手机上的声音分类模型 YAMNet 每 0.25 秒的判断（[SoundClassifier]），交给 Flutter；是不是两声狗叫由
 * lib/core/bark_detector.dart 判断；声音只在内存里过一下，不录音、不保存、不上传）、放行、拒接、关掉。
 */
class CallPlugin(private val activity: Activity, messenger: BinaryMessenger) : TextToSpeech.OnInitListener {

    companion object {
        private const val REQ_MIC = 7
    }

    private val main = Handler(Looper.getMainLooper())
    private val channel = MethodChannel(messenger, "zwjsg/call")
    private var soundSink: EventChannel.EventSink? = null

    private var ringing = false
    private var ringtone: Ringtone? = null
    private var vibrator: Vibrator? = null
    private var tone: MediaPlayer? = null

    /** 要说话时才开系统语音，主界面注册这一份时不白占 */
    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var pendingSpeech: String? = null

    private var listener: MicListener? = null
    private var permissionResult: MethodChannel.Result? = null

    /** 声音分类模型：第一次听狗叫时在后台装好，之后一直用；装不上是 null（只按音量算） */
    private var classifier: SoundClassifier? = null
    private var classifierLoaded = false

    /** 每次开始听、叫停都加 1：在后台装模型的时候 Flutter 已经叫停了，就不开麦克风 */
    private var listenTicket = 0

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "pending" -> background(result) { pendingPayload() }
                "ring" -> {
                    ring()
                    result.success(null)
                }
                "stopRing" -> {
                    stopRing()
                    result.success(null)
                }
                "tone" -> {
                    playTone(call.argument<String>("name"))
                    result.success(null)
                }
                "playVoice" -> result.success(playVoice(call.argument<String>("asset")))
                "speak" -> {
                    speak(call.argument<String>("text"))
                    result.success(null)
                }
                "stopSpeaking" -> {
                    stopSpeaking()
                    result.success(null)
                }
                "startListening" -> startListening(result)
                "stopListening" -> {
                    stopListening()
                    result.success(null)
                }
                "grant" -> background(result) { grant(call.argument<String>("lockId")) }
                "decline" -> {
                    call.argument<String>("lockId")?.let { LockStore(activity).declineToday(it) }
                    result.success(null)
                }
                // 接了又挂了：不放行也不锁死，下次打开那个 App 还会来电
                "hangUp" -> result.success(null)
                "close" -> {
                    close(call.argument<Boolean>("granted") == true)
                    result.success(null)
                }
                "openSettings" -> {
                    activity.startActivity(
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${activity.packageName}"))
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, "zwjsg/bark_sounds").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                soundSink = events
            }

            override fun onCancel(arguments: Any?) {
                soundSink = null
                stopListening()
            }
        })
    }

    /** 要算用时的放到后台线程，结果回主线程 */
    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        Thread {
            val outcome = runCatching(work)
            main.post { outcome.fold({ result.success(it) }, { result.error("CALL_FAILED", it.message, null) }) }
        }.start()
    }

    /** 无障碍服务交过来的来电；今天一共刷了多久交给 Flutter，按狗度规则算狗版的你现在是第几阶段 */
    private fun pendingPayload(): Map<String, Any?>? {
        val intent = activity.intent
        val lockId = intent.getStringExtra(CallReminderActivity.EXTRA_LOCK_ID) ?: return null
        val limit = intent.getIntExtra(CallReminderActivity.EXTRA_LIMIT, 0)
        val today = if (TodayUsage.hasPermission(activity)) TodayUsage.compute(activity) else null
        return mapOf(
            "lockId" to lockId,
            "label" to (intent.getStringExtra(CallReminderActivity.EXTRA_LABEL) ?: "这个 App"),
            "limitMinutes" to limit,
            "dogPercent" to intent.getIntExtra(CallReminderActivity.EXTRA_DOG_PERCENT, 0).takeIf { it > 0 },
            "usedMinutes" to intent.getIntExtra(CallReminderActivity.EXTRA_USED, limit),
            "todayMinutes" to today?.let { TodayUsage.toMin(it.foregroundMs.values.sum()) },
            "locked" to intent.getBooleanExtra(CallReminderActivity.EXTRA_LOCKED, false),
        )
    }

    // 响铃

    /** 手机自己的来电铃声一直循环、震动；静音模式下跟系统来电一样不响也不震 */
    fun ring() {
        if (ringing) return
        ringing = true
        ringtone = runCatching {
            RingtoneManager.getRingtone(activity, RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE))
        }.getOrNull()?.apply {
            audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) isLooping = true
            play()
        }
        val audio = activity.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        if (audio?.ringerMode == AudioManager.RINGER_MODE_SILENT) return
        @Suppress("DEPRECATION")
        vibrator = (activity.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator)?.takeIf { it.hasVibrator() }?.apply {
            val pattern = longArrayOf(0, 1000, 1000)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrate(VibrationEffect.createWaveform(pattern, 0))
            } else {
                vibrate(pattern, 0)
            }
        }
    }

    fun stopRing() {
        ringing = false
        ringtone?.stop()
        ringtone = null
        vibrator?.cancel()
        vibrator = null
    }

    /** 接通、挂断的提示音：Flutter 资源 assets/sounds/<name>.wav */
    private fun playTone(name: String?) {
        if (name == null) return
        tone?.release()
        tone = runCatching {
            val key = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset("assets/sounds/$name.wav")
            activity.assets.openFd(key).use { fd ->
                MediaPlayer().apply {
                    setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_MEDIA)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .build()
                    )
                    setDataSource(fd.fileDescriptor, fd.startOffset, fd.length)
                    prepare()
                    setOnCompletionListener { player ->
                        player.release()
                        if (tone === player) tone = null
                    }
                    start()
                }
            }
        }.getOrNull()
    }

    // 狗版的你说话

    /** 打包在 App 里的语音（提前用 MiniMax 合成、加好电话音效）；正在放的那一句 */
    private var voice: MediaPlayer? = null

    /** 放一句打包好的语音（Flutter 资源路径），返回时长（毫秒）；找不到、放不了返回 null，Flutter 改用系统语音念 */
    private fun playVoice(asset: String?): Int? {
        if (asset == null) return null
        stopSpeaking()
        val player = runCatching {
            val key = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(asset)
            activity.assets.openFd(key).use { fd ->
                MediaPlayer().apply {
                    setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_MEDIA)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                            .build()
                    )
                    setDataSource(fd.fileDescriptor, fd.startOffset, fd.length)
                    prepare()
                    setOnCompletionListener { done ->
                        done.release()
                        if (voice === done) voice = null
                    }
                    start()
                }
            }
        }.getOrNull() ?: return null
        voice = player
        return player.duration.takeIf { it > 0 }
    }

    override fun onInit(status: Int) {
        if (status != TextToSpeech.SUCCESS) return
        val lang = tts?.setLanguage(Locale.SIMPLIFIED_CHINESE) ?: TextToSpeech.LANG_NOT_SUPPORTED
        ttsReady = lang >= TextToSpeech.LANG_AVAILABLE
        tts?.setPitch(1.15f)
        pendingSpeech?.let { speak(it) }
    }

    /** 手机没有中文语音就不念，屏幕上有字 */
    private fun speak(text: String?) {
        if (text.isNullOrEmpty()) return
        if (tts == null) tts = TextToSpeech(activity, this)
        if (!ttsReady) {
            pendingSpeech = text
            return
        }
        pendingSpeech = null
        tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "dog_call")
    }

    private fun stopSpeaking() {
        pendingSpeech = null
        tts?.stop()
        voice?.let {
            runCatching { it.stop() }
            it.release()
        }
        voice = null
    }

    // 听狗叫

    private fun startListening(result: MethodChannel.Result) {
        stopRing()
        stopSpeaking()
        // 6.0 以前装的时候就给了权限
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED
        ) {
            permissionResult?.success("denied")
            permissionResult = result
            activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), REQ_MIC)
            return
        }
        listen(result)
    }

    fun onPermissionResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode != REQ_MIC) return
        val result = permissionResult ?: return
        permissionResult = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            listen(result)
        } else {
            result.success("denied")
        }
    }

    /** 开麦克风：'listening'（音量 + 声音分类）/ 'levels'（模型装不上，只有音量）/ 'failed'（麦克风打不开） */
    private fun listen(result: MethodChannel.Result) {
        stopListening()
        val ticket = listenTicket
        // 第一次要把 4 MB 的模型装进内存，放到后台做，不卡界面
        Thread {
            val classifier = loadClassifier()
            main.post {
                // 装模型的时候已经叫停了（挂断、切走）
                if (ticket != listenTicket) {
                    result.success("failed")
                    return@post
                }
                lateinit var current: MicListener
                current = MicListener(
                    classifier,
                    onLevel = { db -> main.post { if (listener === current) soundSink?.success(listOf(db)) } },
                    onWindow = { window -> main.post { if (listener === current) soundSink?.success(window) } },
                )
                if (!current.start()) {
                    result.success("failed")
                    return@post
                }
                listener = current
                result.success(if (classifier != null) "listening" else "levels")
            }
        }.start()
    }

    @Synchronized
    private fun loadClassifier(): SoundClassifier? {
        if (!classifierLoaded) {
            classifier = SoundClassifier.create(activity)
            classifierLoaded = true
        }
        return classifier
    }

    private fun stopListening() {
        listenTicket++
        listener?.stop()
        listener = null
    }

    // 放行、关掉

    /** 学会两声狗叫：再玩 10 分钟，再用满 10 分钟无障碍服务又会来电 */
    private fun grant(lockId: String?): Boolean {
        val store = LockStore(activity)
        val lock = store.all().firstOrNull { it.id == lockId } ?: return false
        if (store.isDeclinedToday(lock.id)) return false
        val usedMs = if (TodayUsage.hasPermission(activity)) {
            LockStore.usedMs(lock, TodayUsage.compute(activity))
        } else {
            activity.intent.getIntExtra(CallReminderActivity.EXTRA_USED, lock.minutes) * 60_000L
        }
        store.snooze(lock.id, usedMs)
        return true
    }

    /** 放行了：关掉来电页，回到那个 App；没放行（拒接、挂断、锁死了）：回桌面 */
    private fun close(granted: Boolean) {
        stopAll()
        // 主界面的“试一下来电”由 Flutter 自己关，不能把主界面关掉
        if (activity !is CallReminderActivity) return
        if (!granted) {
            activity.startActivity(
                Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        }
        activity.finish()
    }

    fun pause() = stopAll()

    private fun stopAll() {
        stopRing()
        stopSpeaking()
        stopListening()
    }

    fun dispose() {
        stopAll()
        synchronized(this) {
            classifier?.close()
            classifier = null
        }
        tts?.shutdown()
        tts = null
        tone?.release()
        tone = null
        permissionResult?.success("denied")
        permissionResult = null
        channel.setMethodCallHandler(null)
    }
}

/**
 * 开麦克风（16 kHz 单声道）：每 20 毫秒算一次音量（dBFS）交出去；有 [classifier] 的话，每 0.25 秒把最近 0.975 秒的声音
 * 交给它分类，结果也交出去：{'end': 毫秒, 'length': 毫秒, 'labels': {类别名: 分数}}，时间从开始听算起，跟音量同一条时间线。
 * 声音只在内存里过一下，不录音、不保存、不上传。
 */
private class MicListener(
    private val classifier: SoundClassifier?,
    private val onLevel: (Double) -> Unit,
    private val onWindow: (Map<String, Any>) -> Unit,
) {

    companion object {
        /** 每隔多少个采样分类一次（0.25 秒） */
        private const val HOP = SoundClassifier.SAMPLE_RATE / 4
    }

    /** 外面叫停了（离开来电页、超时、狗版的你插话）：读完这一帧就收 */
    @Volatile
    private var stopped = false

    /** 分类放到单独的线程：读麦克风的线程不能停 */
    private val worker = if (classifier != null) Executors.newSingleThreadExecutor() else null

    /** 上一次还没算完就跳过这一次 */
    private val busy = AtomicBoolean(false)

    /** 调用前要先拿到麦克风权限；麦克风打不开（别的 App 在用）返回 false */
    @SuppressLint("MissingPermission")
    fun start(): Boolean {
        val rate = SoundClassifier.SAMPLE_RATE
        val frame = ShortArray(rate / 50)
        val record = runCatching {
            val min = AudioRecord.getMinBufferSize(rate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
            AudioRecord(
                MediaRecorder.AudioSource.MIC, rate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT,
                // 半秒的缓冲：分类在别的线程算，读得慢一点也不丢
                max(min, rate),
            )
        }.getOrNull()
        if (record == null || record.state != AudioRecord.STATE_INITIALIZED) {
            record?.release()
            worker?.shutdown()
            return false
        }
        Thread {
            // 最近 0.975 秒的声音，转着圈写
            val ring = FloatArray(SoundClassifier.WINDOW)
            var total = 0L
            var sinceLast = 0
            try {
                record.startRecording()
                while (!stopped) {
                    val n = record.read(frame, 0, frame.size)
                    if (n < 0) break
                    if (n == 0) continue
                    var sum = 0.0
                    for (i in 0 until n) {
                        val v = frame[i] / 32768f
                        sum += v * v
                        ring[(total % SoundClassifier.WINDOW).toInt()] = v
                        total++
                    }
                    onLevel(20 * log10(max(sqrt(sum / n), 1e-5)))
                    sinceLast += n
                    if (classifier != null && sinceLast >= HOP && busy.compareAndSet(false, true)) {
                        sinceLast = 0
                        // 按时间顺序抄出来；刚开始听不满 0.975 秒的，前面补静音
                        val window = FloatArray(SoundClassifier.WINDOW)
                        val first = total - SoundClassifier.WINDOW
                        for (i in 0 until SoundClassifier.WINDOW) {
                            val at = first + i
                            window[i] = if (at < 0) 0f else ring[(at % SoundClassifier.WINDOW).toInt()]
                        }
                        val endMs = total * 1000 / rate
                        worker!!.execute {
                            try {
                                if (!stopped) {
                                    val labels = classifier.classify(window)
                                    onWindow(mapOf("end" to endMs, "length" to SoundClassifier.WINDOW_MS, "labels" to labels))
                                }
                            } catch (e: Exception) {
                                // 这一次没算出来就算了，下一次接着算
                            } finally {
                                busy.set(false)
                            }
                        }
                    }
                }
            } catch (e: Exception) {
                // 麦克风被别的 App 占了之类：不再报音量，Flutter 那边到点算没听清，可以再来一次
            } finally {
                runCatching { record.stop() }
                record.release()
                worker?.shutdown()
            }
        }.start()
        return true
    }

    fun stop() {
        stopped = true
    }
}
