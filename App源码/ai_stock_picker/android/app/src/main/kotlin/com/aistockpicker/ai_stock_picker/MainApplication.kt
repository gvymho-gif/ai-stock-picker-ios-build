package com.aistockpicker.ai_stock_picker

import io.flutter.app.FlutterApplication
import androidx.work.Configuration

class MainApplication : FlutterApplication(), Configuration.Provider {
    override fun getWorkManagerConfiguration(): Configuration {
        return Configuration.Builder()
            .setMinimumLoggingLevel(android.util.Log.INFO)
            .build()
    }
}
