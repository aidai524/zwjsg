package com.zwjsg.zwjsg_app

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Size
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import java.util.concurrent.Executor
import java.util.concurrent.Executors

/**
 * 拍照形象的相机（安卓，2026-11-27）：在 App 里开相机拍一张自拍，照片只在内存里，不存进相册、不写文件
 * （系统相机只会把照片写成文件，所以不用它）。默认前置摄像头，可以翻转。
 * 拍到的照片交给 [CartoonCapture]，由 [CartoonPlugin] 拿去卡通化。用 CameraX（Google 的相机库，Apache 2.0）。
 */
class CartoonCameraActivity : Activity(), LifecycleOwner {

    private val registry = LifecycleRegistry(this)
    override val lifecycle: Lifecycle get() = registry

    private val handler = Handler(Looper.getMainLooper())
    private val main = Executor { handler.post(it) }
    private val worker = Executors.newSingleThreadExecutor()
    private lateinit var preview: PreviewView
    private var provider: ProcessCameraProvider? = null
    private var capture: ImageCapture? = null
    private var front = true
    private var busy = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        registry.currentState = Lifecycle.State.CREATED
        CartoonCapture.clear()
        setContentView(layout())
        if (checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
            start()
        } else {
            requestPermissions(arrayOf(Manifest.permission.CAMERA), REQUEST_CAMERA)
        }
    }

    override fun onStart() {
        super.onStart()
        registry.currentState = Lifecycle.State.STARTED
    }

    override fun onResume() {
        super.onResume()
        registry.currentState = Lifecycle.State.RESUMED
    }

    override fun onPause() {
        registry.currentState = Lifecycle.State.STARTED
        super.onPause()
    }

    override fun onStop() {
        registry.currentState = Lifecycle.State.CREATED
        super.onStop()
    }

    override fun onDestroy() {
        registry.currentState = Lifecycle.State.DESTROYED
        provider?.unbindAll()
        worker.shutdown()
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_CAMERA) return
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            start()
        } else {
            fail("没有相机权限：去系统设置里允许“再玩我是狗”使用相机，或者从相册选一张")
        }
    }

    private fun start() {
        val future = ProcessCameraProvider.getInstance(this)
        future.addListener({
            val p = runCatching { future.get() }.getOrNull() ?: return@addListener fail("相机打不开，从相册选一张吧")
            provider = p
            if (!runCatching { p.hasCamera(CameraSelector.DEFAULT_FRONT_CAMERA) }.getOrDefault(false)) front = false
            bind()
        }, main)
    }

    private fun bind() {
        val p = provider ?: return
        val selector = if (front) CameraSelector.DEFAULT_FRONT_CAMERA else CameraSelector.DEFAULT_BACK_CAMERA
        // 不要几千万像素的原图：卡通化只用 288 的头像，1280 左右就够，内存也小
        val resolution = ResolutionSelector.Builder()
            .setResolutionStrategy(
                ResolutionStrategy(Size(1280, 960), ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER)
            )
            .build()
        val shot = ImageCapture.Builder()
            .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
            .setResolutionSelector(resolution)
            .build()
        val view = Preview.Builder().build().also { it.setSurfaceProvider(preview.surfaceProvider) }
        try {
            p.unbindAll()
            p.bindToLifecycle(this, selector, view, shot)
            capture = shot
        } catch (e: Exception) {
            fail("相机打不开，从相册选一张吧")
        }
    }

    private fun shoot() {
        val shot = capture ?: return
        if (busy) return
        busy = true
        shot.takePicture(worker, object : ImageCapture.OnImageCapturedCallback() {
            override fun onCaptureSuccess(image: ImageProxy) {
                val bitmap = try {
                    val buffer = image.planes[0].buffer
                    val bytes = ByteArray(buffer.remaining()).also { buffer.get(it) }
                    PhotoDecoder.decode(bytes, rotation = image.imageInfo.rotationDegrees, useExif = false)
                } catch (e: Exception) {
                    null
                } finally {
                    image.close()
                }
                handler.post {
                    if (bitmap == null) {
                        busy = false
                        fail("照片没拍好，再拍一张")
                    } else {
                        CartoonCapture.photo = bitmap
                        setResult(RESULT_OK)
                        finish()
                    }
                }
            }

            override fun onError(exception: ImageCaptureException) {
                handler.post {
                    busy = false
                    fail("照片没拍好，再拍一张")
                }
            }
        })
    }

    private fun fail(message: String) {
        CartoonCapture.error = message
        setResult(RESULT_CANCELED)
        finish()
    }

    /** 全屏取景，上面一句提示，下面“取消”、快门、“翻转” */
    private fun layout(): View {
        val dp = resources.displayMetrics.density
        val root = FrameLayout(this).apply { setBackgroundColor(Color.BLACK) }
        preview = PreviewView(this).apply { scaleType = PreviewView.ScaleType.FILL_CENTER }
        root.addView(preview, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))

        val tip = TextView(this).apply {
            text = "正脸，光线亮一点。别戴口罩，狗不戴口罩。"
            setTextColor(Color.WHITE)
            textSize = 15f
            gravity = Gravity.CENTER
            setPadding((16 * dp).toInt(), (48 * dp).toInt(), (16 * dp).toInt(), (12 * dp).toInt())
            setBackgroundColor(0x66000000)
        }
        root.addView(tip, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.TOP))

        val bar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding((24 * dp).toInt(), (16 * dp).toInt(), (24 * dp).toInt(), (40 * dp).toInt())
            setBackgroundColor(0x66000000)
        }
        fun label(text: String, onClick: () -> Unit) = TextView(this).apply {
            this.text = text
            setTextColor(Color.WHITE)
            textSize = 17f
            gravity = Gravity.CENTER
            setOnClickListener { onClick() }
        }
        bar.addView(label("取消") { setResult(RESULT_CANCELED); finish() }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        val shutter = View(this).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.WHITE)
                setStroke((5 * dp).toInt(), 0xFFFFD23F.toInt())
            }
            contentDescription = "拍照"
            setOnClickListener { shoot() }
        }
        bar.addView(shutter, LinearLayout.LayoutParams((72 * dp).toInt(), (72 * dp).toInt()))
        bar.addView(label("翻转") { front = !front; bind() }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        root.addView(bar, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.BOTTOM))
        return root
    }

    companion object {
        private const val REQUEST_CAMERA = 7302
    }
}

/** 相机页拍到的照片（只在内存里），交给 CartoonPlugin 后清掉 */
object CartoonCapture {
    @Volatile var photo: android.graphics.Bitmap? = null
    @Volatile var error: String? = null

    fun clear() {
        photo = null
        error = null
    }

    fun take(): android.graphics.Bitmap? = photo.also { clear() }
}
