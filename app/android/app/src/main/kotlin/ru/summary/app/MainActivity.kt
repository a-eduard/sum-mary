package ru.summary.app

import android.content.Intent
import android.os.Build
import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sammari/foreground")
            .setMethodCallHandler { call, result ->
                val intent = Intent(this, RecordingService::class.java)
                when (call.method) {
                    "start" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent)
                        else startService(intent)
                        result.success(null)
                    }
                    "stop" -> { stopService(intent); result.success(null) }
                    else -> result.notImplemented()
                }
            }
        // Свободное место во внутренней памяти — чтобы запись не оборвалась на середине лекции.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sammari/storage")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "freeBytes" -> result.success(StatFs(filesDir.absolutePath).availableBytes)
                    else -> result.notImplemented()
                }
            }
    }
}
