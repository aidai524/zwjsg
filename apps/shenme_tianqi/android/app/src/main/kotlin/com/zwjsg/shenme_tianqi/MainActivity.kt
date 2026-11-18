package com.zwjsg.shenme_tianqi

import com.zwjsg.shenme_tianqi.widget.HomeWidgetChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 本 App 自己的原生通道：桌面小组件
        HomeWidgetChannel.register(this, flutterEngine.dartExecutor.binaryMessenger)
    }
}
