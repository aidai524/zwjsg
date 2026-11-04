package com.zwjsg.zwjsg_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        UsagePlugin(this).register(flutterEngine.dartExecutor.binaryMessenger)
    }
}
