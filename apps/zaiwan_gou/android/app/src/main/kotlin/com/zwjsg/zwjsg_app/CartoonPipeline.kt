package com.zwjsg.zwjsg_app

import android.content.Context
import android.graphics.Bitmap
import org.tensorflow.lite.Interpreter
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.MappedByteBuffer
import java.nio.channels.FileChannel
import kotlin.math.atan2
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * 安卓的拍照形象（2026-11-27）：照片只在内存里，和 iOS 的 CartoonLab.swift 一样出 288x288 的卡通图和人像蒙版，
 * 交给 Flutter 画成平涂墨线贴纸（packages/avatar_engine 的 PhotoSticker）。
 *
 * 1. MediaPipe 的 BlazeFace（短距离）找脸，多张取最大的
 * 2. MediaPipe 的人脸网格（478 个点）找 5 个点：两眼瞳孔、鼻尖、两个嘴角
 * 3. 按 DCT-Net 官方模板做相似变换，对齐成 288x288，图外填白
 * 4. DCT-Net 日漫头像模型（TFLite，FP16 权重）卡通化
 * 5. MediaPipe 自拍抠图：贴着脸裁的图模型认不出人，往外放大 1.5 倍、看得到头和肩膀再抠，抠完缩回 288
 *
 * 模型在 assets/cartoon/（来源和转换见 tools/cartoon/README.md），用已经带着的 LiteRT 1.4.2 跑。
 * 每一步和 tools/cartoon/android_pipeline.py 一一对应：改了这里要在 Mac 上用那个脚本对一遍。
 */
class CartoonPipeline(context: Context) : AutoCloseable {

    class Result(val rgba: ByteArray, val mask: ByteArray, val faces: Int)

    class NoFace(message: String) : Exception(message)

    private val detector = interpreter(context, "cartoon/face_detector.tflite")
    private val mesh = interpreter(context, "cartoon/face_landmarks_detector.tflite")
    private val segmenter = interpreter(context, "cartoon/selfie_segmenter.tflite")
    private val cartoon = interpreter(context, "cartoon/dctnet_anime_head.tflite")

    /** 照片（已经转正、长边不超过 1280）→ 卡通图和蒙版。找不到脸时抛 [NoFace]，message 可以直接给用户看 */
    fun run(photo: Bitmap): Result {
        val w = photo.width
        val h = photo.height
        val pixels = IntArray(w * h).also { photo.getPixels(it, 0, w, 0, 0, w, h) }
        val img = Image(pixels, w, h)

        val faces = detect(img)
        if (faces.isEmpty()) throw NoFace("没找到人脸，换一张正脸、光线亮一点的照片")
        val face = faces.maxByOrNull { it.box[2] - it.box[0] }!!
        val (points, presence) = landmarks(img, face)
        if (presence < 0.5f) throw NoFace("五官没找全，换一张正脸照片")

        // 5 个点：左眼、右眼（按图上左右）、鼻尖、左嘴角、右嘴角
        val eyes = listOf(point(points, 468), point(points, 473)).sortedBy { it[0] }
        val mouth = listOf(point(points, 61), point(points, 291)).sortedBy { it[0] }
        val five = arrayOf(eyes[0], eyes[1], point(points, 4), mouth[0], mouth[1])
        val toAligned = similarity(five, TARGET)
        val toPhoto = invert(toAligned)

        // 对齐：288 头像的像素 → 原图，图外填白
        val aligned = sample(img, toPhoto, SIZE, SIZE, 255f)
        val rgba = cartoonize(aligned)
        val mask = personMask(img, toPhoto)
        return Result(rgba, mask, faces.size)
    }

    override fun close() {
        detector.close()
        mesh.close()
        segmenter.close()
        cartoon.close()
    }

    // MARK: 1. 找脸（BlazeFace 短距离，128x128，-1~1）

    private class Face(val score: Float, val box: FloatArray, val keypoints: Array<FloatArray>)

    private fun detect(img: Image): List<Face> {
        val scale = 128f / max(img.w, img.h)
        val padX = (128 - img.w * scale) / 2
        val padY = (128 - img.h * scale) / 2
        // 128 的输入像素 → 原图像素（等比缩放，上下或左右补黑边）
        val toPhoto = floatArrayOf(1 / scale, 0f, -padX / scale, 0f, 1 / scale, -padY / scale)
        val input = sample(img, toPhoto, 128, 128, 0f)
        val buffer = floatBuffer(128 * 128 * 3)
        for (v in input) buffer.putFloat(v / 127.5f - 1f)
        buffer.rewind()

        val regressors = Array(1) { Array(ANCHOR_COUNT) { FloatArray(16) } }
        val scores = Array(1) { Array(ANCHOR_COUNT) { FloatArray(1) } }
        val outputs = HashMap<Int, Any>()
        for (i in 0 until detector.outputTensorCount) {
            outputs[i] = if (detector.getOutputTensor(i).shape().last() == 16) regressors else scores
        }
        detector.runForMultipleInputsOutputs(arrayOf(buffer), outputs)

        val order = (0 until ANCHOR_COUNT).sortedByDescending { scores[0][it][0] }
        val found = ArrayList<Face>()
        for (i in order) {
            val score = sigmoid(scores[0][i][0])
            if (score < 0.5f) break
            val r = regressors[0][i]
            val ax = ANCHORS[i * 2]
            val ay = ANCHORS[i * 2 + 1]
            val cx = r[0] / 128 + ax
            val cy = r[1] / 128 + ay
            val bw = r[2] / 128
            val bh = r[3] / 128
            val box = floatArrayOf(cx - bw / 2, cy - bh / 2, cx + bw / 2, cy + bh / 2)
            if (found.any { iou(box, it.box) > 0.3f }) continue
            val keypoints = Array(6) { k -> floatArrayOf(r[4 + 2 * k] / 128 + ax, r[5 + 2 * k] / 128 + ay) }
            found.add(Face(score, box, keypoints))
        }
        // 0~1 的输入坐标 → 原图像素
        fun x(v: Float) = (v * 128 - padX) / scale
        fun y(v: Float) = (v * 128 - padY) / scale
        return found.map { f ->
            Face(
                f.score,
                floatArrayOf(x(f.box[0]), y(f.box[1]), x(f.box[2]), y(f.box[3])),
                Array(6) { k -> floatArrayOf(x(f.keypoints[k][0]), y(f.keypoints[k][1])) },
            )
        }
    }

    // MARK: 2. 人脸网格（256x256，0~1）：从找到的脸往外放大 1.5 倍、按两眼摆正后裁出来

    private fun landmarks(img: Image, face: Face): Pair<FloatArray, Float> {
        val (x0, y0, x1, y1) = face.box.toList()
        val cx = (x0 + x1) / 2
        val cy = (y0 + y1) / 2
        // BlazeFace 的第 0、1 个点是右眼、左眼（本人的左右）
        val (rx, ry) = face.keypoints[0].toList()
        val (lx, ly) = face.keypoints[1].toList()
        val pi = Math.PI.toFloat()
        // 归到 [−π, π)：Kotlin 的 % 可能是负数，先加一圈再取余
        val rot = ((-atan2(-(ly - ry), lx - rx) + pi) % (2 * pi) + 2 * pi) % (2 * pi) - pi
        val side = max(x1 - x0, y1 - y0) * 1.5f
        val c = cos(rot)
        val s = sin(rot)
        val k = side / 256
        // 256 的裁图像素 (u, v) → 原图：((u − 128)·k, (v − 128)·k) 转 rot，再加中心
        val toPhoto = floatArrayOf(
            c * k, -s * k, cx - 128 * k * c + 128 * k * s,
            s * k, c * k, cy - 128 * k * s - 128 * k * c,
        )
        val input = sample(img, toPhoto, 256, 256, 0f)
        val buffer = floatBuffer(256 * 256 * 3)
        for (v in input) buffer.putFloat(v / 255f)
        buffer.rewind()

        val pts = Array(1) { Array(1) { Array(1) { FloatArray(1434) } } }
        val presence = Array(1) { Array(1) { Array(1) { FloatArray(1) } } }
        val outputs = HashMap<Int, Any>()
        for (i in 0 until mesh.outputTensorCount) {
            val shape = mesh.getOutputTensor(i).shape()
            outputs[i] = when {
                shape.last() == 1434 -> pts
                shape.size == 4 -> presence
                else -> Array(shape[0]) { FloatArray(shape.last()) }
            }
        }
        mesh.runForMultipleInputsOutputs(arrayOf(buffer), outputs)

        val raw = pts[0][0][0]
        val out = FloatArray(478 * 2)
        for (i in 0 until 478) {
            val u = raw[i * 3]
            val v = raw[i * 3 + 1]
            out[i * 2] = toPhoto[0] * u + toPhoto[1] * v + toPhoto[2]
            out[i * 2 + 1] = toPhoto[3] * u + toPhoto[4] * v + toPhoto[5]
        }
        return out to sigmoid(presence[0][0][0][0])
    }

    private fun point(points: FloatArray, i: Int) = floatArrayOf(points[i * 2], points[i * 2 + 1])

    // MARK: 4. 卡通化（288x288，BGR，0~255 进出）

    private fun cartoonize(aligned: FloatArray): ByteArray {
        val input = floatBuffer(SIZE * SIZE * 3)
        for (i in 0 until SIZE * SIZE) {
            input.putFloat(aligned[i * 3 + 2])
            input.putFloat(aligned[i * 3 + 1])
            input.putFloat(aligned[i * 3])
        }
        input.rewind()
        val output = floatBuffer(SIZE * SIZE * 3)
        cartoon.run(input, output)
        output.rewind()
        val rgba = ByteArray(SIZE * SIZE * 4)
        for (i in 0 until SIZE * SIZE) {
            val b = output.float
            val g = output.float
            val r = output.float
            rgba[i * 4] = byte(r)
            rgba[i * 4 + 1] = byte(g)
            rgba[i * 4 + 2] = byte(b)
            rgba[i * 4 + 3] = 255.toByte()
        }
        return rgba
    }

    // MARK: 5. 自拍抠图（256x256，0~1）

    private fun personMask(img: Image, toPhoto: FloatArray): ByteArray {
        // 256 的抠图输入像素 c → 288 头像坐标 a = (c·288/256 − 144)·zoom + 144 → 原图
        val k = SIZE / 256f * ZOOM
        val shift = 144 - 144 * ZOOM
        val toAligned = floatArrayOf(k, 0f, shift, 0f, k, shift)
        val input = sample(img, compose(toPhoto, toAligned), 256, 256, 255f)
        val buffer = floatBuffer(256 * 256 * 3)
        for (v in input) buffer.putFloat(v / 255f)
        buffer.rewind()
        val output = floatBuffer(256 * 256)
        segmenter.run(buffer, output)
        output.rewind()
        val confidence = FloatArray(256 * 256) { output.float }

        // 288 头像像素 a → 抠图输入像素 c = ((a − 144)/zoom + 144)·256/288
        val back = floatArrayOf(1 / k, 0f, (144 - 144 / ZOOM) * 256 / SIZE, 0f, 1 / k, (144 - 144 / ZOOM) * 256 / SIZE)
        val mask = sampleChannel(confidence, 256, 256, back, SIZE, SIZE, 0f)
        return ByteArray(SIZE * SIZE) { byte(mask[it] * 255) }
    }

    // MARK: 工具

    /** ARGB 像素 */
    private class Image(val pixels: IntArray, val w: Int, val h: Int)

    companion object {
        private const val SIZE = 288

        /** 抠图往外放大几倍 */
        private const val ZOOM = 1.5f

        /** 官方 96x112 模板（各加 1），x 再加 8 补成 112x112 正方形，按 ratio 0.75 缩，再放大到 288（和 iOS 一样） */
        private val TARGET: Array<FloatArray> = arrayOf(
            floatArrayOf(30.29459953f, 51.69630051f),
            floatArrayOf(65.53179932f, 51.50139999f),
            floatArrayOf(48.02519989f, 71.73660278f),
            floatArrayOf(33.54930115f, 92.3655014f),
            floatArrayOf(62.72990036f, 92.20410156f),
        ).map { (x, y) -> floatArrayOf(((x + 9 - 56) * 0.75f + 56) * SIZE / 112, ((y + 1 - 56) * 0.75f + 56) * SIZE / 112) }
            .toTypedArray()

        private const val ANCHOR_COUNT = 896

        /** BlazeFace 短距离模型的锚点：步长 8 的一层每格 2 个，步长 16 的三层合起来每格 6 个，宽高都是 1 */
        private val ANCHORS: FloatArray = run {
            val strides = intArrayOf(8, 16, 16, 16)
            val out = ArrayList<Float>()
            var layer = 0
            while (layer < strides.size) {
                var last = layer
                while (last + 1 < strides.size && strides[last + 1] == strides[layer]) last++
                val perCell = 2 * (last - layer + 1)
                val fm = ceil(128.0 / strides[layer]).toInt()
                for (y in 0 until fm) for (x in 0 until fm) repeat(perCell) {
                    out.add((x + 0.5f) / fm)
                    out.add((y + 0.5f) / fm)
                }
                layer = last + 1
            }
            check(out.size == ANCHOR_COUNT * 2)
            out.toFloatArray()
        }

        private fun interpreter(context: Context, asset: String): Interpreter {
            val model: MappedByteBuffer = context.assets.openFd(asset).use { fd ->
                FileInputStream(fd.fileDescriptor).channel.use { channel ->
                    channel.map(FileChannel.MapMode.READ_ONLY, fd.startOffset, fd.declaredLength)
                }
            }
            return Interpreter(model, Interpreter.Options().setNumThreads(4))
        }

        private fun floatBuffer(count: Int): ByteBuffer = ByteBuffer.allocateDirect(count * 4).order(ByteOrder.nativeOrder())

        private fun sigmoid(x: Float) = 1f / (1f + exp(-x.coerceIn(-100f, 100f)))

        private fun byte(v: Float) = v.coerceIn(0f, 255f).toInt().toByte()

        private fun iou(a: FloatArray, b: FloatArray): Float {
            val ix = max(0f, min(a[2], b[2]) - max(a[0], b[0]))
            val iy = max(0f, min(a[3], b[3]) - max(a[1], b[1]))
            val inter = ix * iy
            val union = (a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - inter
            return if (union > 0) inter / union else 0f
        }

        /** 最小二乘相似变换（旋转 + 等比缩放 + 平移，不镜像）：src → dst，返回 [a, −b, tx, b, a, ty] */
        private fun similarity(src: Array<FloatArray>, dst: Array<FloatArray>): FloatArray {
            val n = src.size
            val smx = src.sumOf { it[0].toDouble() } / n
            val smy = src.sumOf { it[1].toDouble() } / n
            val dmx = dst.sumOf { it[0].toDouble() } / n
            val dmy = dst.sumOf { it[1].toDouble() } / n
            var dot = 0.0
            var cross = 0.0
            var norm = 0.0
            for (i in 0 until n) {
                val sx = src[i][0] - smx
                val sy = src[i][1] - smy
                val dx = dst[i][0] - dmx
                val dy = dst[i][1] - dmy
                dot += sx * dx + sy * dy
                cross += sx * dy - sy * dx
                norm += sx * sx + sy * sy
            }
            val a = dot / norm
            val b = cross / norm
            return floatArrayOf(
                a.toFloat(), (-b).toFloat(), (dmx - (a * smx - b * smy)).toFloat(),
                b.toFloat(), a.toFloat(), (dmy - (b * smx + a * smy)).toFloat(),
            )
        }

        private fun invert(m: FloatArray): FloatArray {
            val det = m[0] * m[4] - m[1] * m[3]
            val a = m[4] / det
            val b = -m[1] / det
            val c = -m[3] / det
            val d = m[0] / det
            return floatArrayOf(a, b, -(a * m[2] + b * m[5]), c, d, -(c * m[2] + d * m[5]))
        }

        /** 先做 [inner] 再做 [outer] */
        private fun compose(outer: FloatArray, inner: FloatArray) = floatArrayOf(
            outer[0] * inner[0] + outer[1] * inner[3], outer[0] * inner[1] + outer[1] * inner[4],
            outer[0] * inner[2] + outer[1] * inner[5] + outer[2],
            outer[3] * inner[0] + outer[4] * inner[3], outer[3] * inner[1] + outer[4] * inner[4],
            outer[3] * inner[2] + outer[4] * inner[5] + outer[5],
        )

        /**
         * 按 [m]（输出像素中心 → 原图坐标）把照片双线性采样成 outW × outH，得到 RGB 浮点（0~255），图外填 [fill]。
         * 像素中心的取法和 Python 原型一样：输出像素 (u, v) 的中心是 (u + 0.5, v + 0.5)，原图像素 (x, y) 的中心也是
         */
        private fun sample(img: Image, m: FloatArray, outW: Int, outH: Int, fill: Float): FloatArray {
            val out = FloatArray(outW * outH * 3)
            for (v in 0 until outH) {
                for (u in 0 until outW) {
                    val fu = u + 0.5f
                    val fv = v + 0.5f
                    val x = m[0] * fu + m[1] * fv + m[2] - 0.5f
                    val y = m[3] * fu + m[4] * fv + m[5] - 0.5f
                    val x0 = floor(x).toInt()
                    val y0 = floor(y).toInt()
                    val fx = x - x0
                    val fy = y - y0
                    var r = 0f
                    var g = 0f
                    var b = 0f
                    for (dy in 0..1) for (dx in 0..1) {
                        val wgt = (if (dx == 0) 1 - fx else fx) * (if (dy == 0) 1 - fy else fy)
                        val xi = x0 + dx
                        val yi = y0 + dy
                        if (xi in 0 until img.w && yi in 0 until img.h) {
                            val p = img.pixels[yi * img.w + xi]
                            r += ((p shr 16) and 0xFF) * wgt
                            g += ((p shr 8) and 0xFF) * wgt
                            b += (p and 0xFF) * wgt
                        } else {
                            r += fill * wgt
                            g += fill * wgt
                            b += fill * wgt
                        }
                    }
                    val o = (v * outW + u) * 3
                    out[o] = r
                    out[o + 1] = g
                    out[o + 2] = b
                }
            }
            return out
        }

        /** 单通道的双线性采样（蒙版用） */
        private fun sampleChannel(src: FloatArray, w: Int, h: Int, m: FloatArray, outW: Int, outH: Int, fill: Float): FloatArray {
            val out = FloatArray(outW * outH)
            for (v in 0 until outH) {
                for (u in 0 until outW) {
                    val fu = u + 0.5f
                    val fv = v + 0.5f
                    val x = m[0] * fu + m[1] * fv + m[2] - 0.5f
                    val y = m[3] * fu + m[4] * fv + m[5] - 0.5f
                    val x0 = floor(x).toInt()
                    val y0 = floor(y).toInt()
                    val fx = x - x0
                    val fy = y - y0
                    var acc = 0f
                    for (dy in 0..1) for (dx in 0..1) {
                        val wgt = (if (dx == 0) 1 - fx else fx) * (if (dy == 0) 1 - fy else fy)
                        val xi = x0 + dx
                        val yi = y0 + dy
                        acc += wgt * (if (xi in 0 until w && yi in 0 until h) src[yi * w + xi] else fill)
                    }
                    out[v * outW + u] = acc
                }
            }
            return out
        }
    }
}
