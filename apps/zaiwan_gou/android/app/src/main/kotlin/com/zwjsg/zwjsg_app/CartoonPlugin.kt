package com.zwjsg.zwjsg_app

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ext.SdkExtensions
import android.provider.MediaStore
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayInputStream
import java.util.concurrent.Executors
import kotlin.math.max

/**
 * 拍照形象（安卓，2026-11-27）：和 iOS 的 CartoonLab.swift 同一个通道 `zwjsg/cartoon`。
 * - `camera`：App 里的相机拍一张（[CartoonCameraActivity]）
 * - `library`：系统的选图器选一张，App 只拿到选的那一张，不要存储权限
 * 照片只读进内存，在内存里转正、缩到长边 1280 以内，交给 [CartoonPipeline]；回给 Flutter 的只有卡通图和人像蒙版
 * （`cartoonRgba`、`mask`，都是 288x288，第一行在最上面）和找到几张脸（`faces`）。没拍、没选就关了回 null。
 */
class CartoonPlugin(private val activity: Activity, messenger: BinaryMessenger) {

    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private var pending: MethodChannel.Result? = null
    private var pipeline: CartoonPipeline? = null

    init {
        MethodChannel(messenger, "zwjsg/cartoon").setMethodCallHandler { call, result ->
            when (call.method) {
                "camera" -> open(result) {
                    activity.startActivityForResult(Intent(activity, CartoonCameraActivity::class.java), REQUEST_CAMERA)
                }
                "library" -> open(result) { activity.startActivityForResult(pickIntent(), REQUEST_LIBRARY) }
                else -> result.notImplemented()
            }
        }
    }

    private fun open(result: MethodChannel.Result, launch: () -> Unit) {
        if (pending != null) return result.error("busy", "上一张还没弄完", null)
        pending = result
        try {
            launch()
        } catch (e: Exception) {
            pending = null
            result.error("open_failed", "打不开，稍后再试", null)
        }
    }

    /** 安卓 13 起（以及装了新版系统组件的 11、12）用系统的照片选择器，更早的用系统的文件选择 */
    private fun pickIntent(): Intent {
        val photoPicker = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU ||
            (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && SdkExtensions.getExtensionVersion(Build.VERSION_CODES.R) >= 2)
        return if (photoPicker) {
            Intent(MediaStore.ACTION_PICK_IMAGES).setType("image/*")
        } else {
            Intent(Intent.ACTION_GET_CONTENT).setType("image/*").addCategory(Intent.CATEGORY_OPENABLE)
        }
    }

    /** MainActivity 转过来的结果；是这里的返回 true */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CAMERA && requestCode != REQUEST_LIBRARY) return false
        val result = pending ?: return true
        pending = null
        if (requestCode == REQUEST_CAMERA) {
            val photo = CartoonCapture.photo
            val error = CartoonCapture.error
            CartoonCapture.clear()
            when {
                resultCode == Activity.RESULT_OK && photo != null -> process(result) { photo }
                error != null -> result.error("lab_failed", error, null)
                else -> result.success(null) // 没拍就关了
            }
        } else {
            val uri = data?.data
            if (resultCode != Activity.RESULT_OK || uri == null) {
                result.success(null) // 没选就关了
            } else {
                process(result) { read(uri) }
            }
        }
        return true
    }

    private fun read(uri: Uri): Bitmap {
        val bytes = activity.contentResolver.openInputStream(uri)?.use { it.readBytes() }
            ?: throw CartoonPipeline.NoFace("照片没读出来")
        return PhotoDecoder.decode(bytes, rotation = 0, useExif = true)
    }

    private fun process(result: MethodChannel.Result, load: () -> Bitmap) {
        worker.execute {
            val outcome = runCatching {
                val photo = load()
                val p = pipeline ?: CartoonPipeline(activity).also { pipeline = it }
                p.run(photo).also { photo.recycle() }
            }
            main.post {
                outcome.fold(
                    { result.success(mapOf("cartoonRgba" to it.rgba, "mask" to it.mask, "faces" to it.faces)) },
                    { e ->
                        val message = if (e is CartoonPipeline.NoFace) e.message else "出错了，换一张试试"
                        result.error("lab_failed", message, null)
                    },
                )
            }
        }
    }

    fun dispose() {
        worker.execute {
            pipeline?.close()
            pipeline = null
        }
        worker.shutdown()
    }

    companion object {
        private const val REQUEST_CAMERA = 7301
        private const val REQUEST_LIBRARY = 7303
    }
}

/** 照片的字节 → 转正、长边不超过 1280 的位图（只在内存里） */
object PhotoDecoder {
    private const val MAX_SIDE = 1280

    /** [rotation] 是相机给的要顺时针转多少度；[useExif] 时按照片自己记的方向转（相册里的照片） */
    fun decode(bytes: ByteArray, rotation: Int, useExif: Boolean): Bitmap {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) throw CartoonPipeline.NoFace("这张照片读不出来，换一张试试")
        var sample = 1
        while (max(bounds.outWidth, bounds.outHeight) / (sample * 2) >= MAX_SIDE) sample *= 2
        val options = BitmapFactory.Options().apply {
            inSampleSize = sample
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        var bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
            ?: throw CartoonPipeline.NoFace("这张照片读不出来，换一张试试")

        val matrix = Matrix()
        val long = max(bitmap.width, bitmap.height)
        if (long > MAX_SIDE) {
            val s = MAX_SIDE.toFloat() / long
            matrix.postScale(s, s)
        }
        if (useExif) {
            val orientation = runCatching {
                ExifInterface(ByteArrayInputStream(bytes)).getAttributeInt(
                    ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL,
                )
            }.getOrDefault(ExifInterface.ORIENTATION_NORMAL)
            when (orientation) {
                ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
                ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
                ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
                ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.postScale(-1f, 1f)
                ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.postScale(1f, -1f)
                ExifInterface.ORIENTATION_TRANSPOSE -> { matrix.postRotate(90f); matrix.postScale(-1f, 1f) }
                ExifInterface.ORIENTATION_TRANSVERSE -> { matrix.postRotate(270f); matrix.postScale(-1f, 1f) }
            }
        } else if (rotation != 0) {
            matrix.postRotate(rotation.toFloat())
        }
        if (!matrix.isIdentity) {
            val turned = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
            if (turned !== bitmap) bitmap.recycle()
            bitmap = turned
        }
        return bitmap
    }
}
