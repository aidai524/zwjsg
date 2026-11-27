package com.zwjsg.zwjsg_app

import android.content.Intent
import com.zwjsg.zwjsg_app.widget.HomeWidgetChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    /** “试一下来电”：和来电页同一套响铃、说话、听狗叫 */
    private var call: CallPlugin? = null

    /** 拍照形象：拍一张或选一张，在手机上卡通化 */
    private var cartoon: CartoonPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        UsagePlugin(this).register(flutterEngine.dartExecutor.binaryMessenger)
        LockPlugin(this).register(flutterEngine.dartExecutor.binaryMessenger)
        // 桌面小组件
        HomeWidgetChannel.register(this, flutterEngine.dartExecutor.binaryMessenger)
        call = CallPlugin(this, flutterEngine.dartExecutor.binaryMessenger)
        cartoon = CartoonPlugin(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    @Deprecated("相机页、选图器的结果还是走 onActivityResult（FlutterActivity 不是 ComponentActivity）")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (cartoon?.onActivityResult(requestCode, resultCode, data) == true) return
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        call?.onPermissionResult(requestCode, grantResults)
    }

    override fun onStop() {
        super.onStop()
        call?.pause()
    }

    override fun onDestroy() {
        call?.dispose()
        call = null
        cartoon?.dispose()
        cartoon = null
        super.onDestroy()
    }
}
