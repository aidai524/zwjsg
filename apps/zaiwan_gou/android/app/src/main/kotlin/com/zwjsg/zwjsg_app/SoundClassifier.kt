package com.zwjsg.zwjsg_app

import android.content.Context
import org.tensorflow.lite.Interpreter
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.channels.FileChannel

/**
 * 听狗叫时给声音分类（2026-11-24）：Google 开源的声音分类模型 YAMNet（Apache 2.0，assets/yamnet.tflite，
 * 来自 MediaPipe 的音频分类模型），用 LiteRT（原来的 TensorFlow Lite）在手机上跑，不联网。
 * 输入最近 0.975 秒、16 kHz 单声道的声音（15600 个 -1..1 的数），输出 521 类声音各自的分数（类别名在 assets/yamnet_labels.txt）。
 * 声音只在内存里过一下，不录音、不保存、不上传。归成哪种声音（狗叫、人声、拍手、吹气）由 Flutter 的 lib/core/sound_labels.dart 定。
 */
class SoundClassifier private constructor(private val interpreter: Interpreter, private val labels: List<String>) {

    companion object {
        const val SAMPLE_RATE = 16_000
        const val WINDOW = 15_600
        const val WINDOW_MS = WINDOW * 1000 / SAMPLE_RATE

        /** 交给 Flutter 的：分数到这么多的类别，最多这么多个 */
        private const val MIN_SCORE = 0.02f
        private const val TOP = 12

        /** 模型或运行库装不上（极少见）返回 null：Flutter 那边只按音量算 */
        fun create(context: Context): SoundClassifier? = runCatching {
            // 模型在安装包里不压缩（build.gradle.kts 的 noCompress），可以直接映射进内存
            val model = context.assets.openFd("yamnet.tflite").use { fd ->
                FileInputStream(fd.fileDescriptor).channel.use { channel ->
                    channel.map(FileChannel.MapMode.READ_ONLY, fd.startOffset, fd.declaredLength)
                }
            }
            val labels = context.assets.open("yamnet_labels.txt").bufferedReader().useLines { lines ->
                lines.map { it.trim() }.toList()
            }
            SoundClassifier(Interpreter(model, Interpreter.Options().setNumThreads(2)), labels)
        }.getOrNull()
    }

    private val input = ByteBuffer.allocateDirect(WINDOW * 4).order(ByteOrder.nativeOrder())
    private val output = ByteBuffer.allocateDirect(interpreter.getOutputTensor(0).numBytes()).order(ByteOrder.nativeOrder())
    private var closed = false

    /** [samples] 是最近 0.975 秒的声音；返回分数够高的几类：类别名 → 分数 */
    @Synchronized
    fun classify(samples: FloatArray): Map<String, Double> {
        if (closed) return emptyMap()
        input.rewind()
        input.asFloatBuffer().put(samples, 0, WINDOW)
        output.rewind()
        interpreter.run(input, output)
        output.rewind()
        val scores = output.asFloatBuffer()
        val n = minOf(scores.remaining(), labels.size)
        return (0 until n)
            .map { it to scores.get(it) }
            .filter { it.second >= MIN_SCORE }
            .sortedByDescending { it.second }
            .take(TOP)
            .associate { labels[it.first] to it.second.toDouble() }
    }

    /** 等正在算的那一次算完再关 */
    @Synchronized
    fun close() {
        if (closed) return
        closed = true
        interpreter.close()
    }
}
