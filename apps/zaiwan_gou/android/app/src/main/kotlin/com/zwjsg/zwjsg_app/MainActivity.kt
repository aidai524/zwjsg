package com.zwjsg.zwjsg_app

import com.zwjsg.zwjsg_app.widget.HomeWidgetChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        UsagePlugin(this).register(flutterEngine.dartExecutor.binaryMessenger)
        LockPlugin(this).register(flutterEngine.dartExecutor.binaryMessenger)
        // 桌面小组件
        HomeWidgetChannel.register(this, flutterEngine.dartExecutor.binaryMessenger)
    }
}
