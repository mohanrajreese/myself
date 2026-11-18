package com.mysticstack.fitbuddy

import android.net.Uri
import androidx.activity.result.contract.ActivityResultContracts
import com.mysticstack.fitbuddy.generated.AlarmApi
import com.mysticstack.fitbuddy.generated.SoundApi
import com.mysticstack.fitbuddy.generated.SystemInfoApi
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import java.util.TimeZone

// FlutterFragmentActivity is required by the biometric prompt (app lock).
class MainActivity : FlutterFragmentActivity() {
    private var pendingSoundPick: ((Uri?) -> Unit)? = null

    // Registered at construction, before the activity starts, as Android requires.
    private val soundPicker = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        pendingSoundPick?.invoke(uri)
        pendingSoundPick = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        SystemInfoApi.setUp(
            flutterEngine.dartExecutor.binaryMessenger,
            object : SystemInfoApi {
                override fun timeZoneId(): String = TimeZone.getDefault().id
            },
        )
        AlarmApi.setUp(flutterEngine.dartExecutor.binaryMessenger, AlarmPlugin(applicationContext))
        SoundApi.setUp(
            flutterEngine.dartExecutor.binaryMessenger,
            SoundPlugin(applicationContext) { callback ->
                pendingSoundPick = callback
                soundPicker.launch(arrayOf("audio/*"))
            },
        )
    }
}
