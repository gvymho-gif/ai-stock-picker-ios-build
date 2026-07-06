package com.aistockpicker.ai_stock_picker

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.nio.charset.Charset

class MainActivity: FlutterActivity() {
    private val CODEC_CHANNEL = "com.aistockpicker/codec"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 保持屏幕常亮
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        // 创建后台监控通知渠道（Android 8.0+）
        createNotificationChannel()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "stock_monitor_channel",
                "蓝图极智监控",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "A 股交易时段止盈止损实时监控"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // GBK 解码通道
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CODEC_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "decodeGbk" -> {
                    try {
                        val bytes = call.argument<ByteArray>("bytes")
                        if (bytes != null) {
                            val text = String(bytes, Charset.forName("GBK"))
                            result.success(text)
                        } else {
                            result.error("INVALID_ARGS", "bytes argument is required", null)
                        }
                    } catch (e: Exception) {
                        result.error("DECODE_ERROR", e.toString(), null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
