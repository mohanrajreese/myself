package com.mysticstack.fitbuddy

import com.mysticstack.fitbuddy.generated.SystemInfoApi
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import java.util.TimeZone

// FlutterFragmentActivity is required by the biometric prompt (app lock).
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        SystemInfoApi.setUp(
            flutterEngine.dartExecutor.binaryMessenger,
            object : SystemInfoApi {
                override fun timeZoneId(): String = TimeZone.getDefault().id
            },
        )
    }
}
