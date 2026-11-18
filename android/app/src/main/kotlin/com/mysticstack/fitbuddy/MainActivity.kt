package com.mysticstack.fitbuddy

import android.Manifest
import android.net.Uri
import androidx.activity.result.contract.ActivityResultContracts
import com.mysticstack.fitbuddy.generated.AlarmApi
import com.mysticstack.fitbuddy.generated.SecurityApi
import com.mysticstack.fitbuddy.generated.SoundApi
import com.mysticstack.fitbuddy.generated.UsageApi
import com.mysticstack.fitbuddy.generated.StepApi
import com.mysticstack.fitbuddy.steps.StepPlugin
import com.mysticstack.fitbuddy.generated.SystemInfoApi
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import java.util.TimeZone

// FlutterFragmentActivity is required by the biometric prompt (app lock).
class MainActivity : FlutterFragmentActivity() {
    private var pendingSoundPick: ((Uri?) -> Unit)? = null
    private var pendingPermission: ((Boolean) -> Unit)? = null

    private val permissionRequest = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        pendingPermission?.invoke(granted)
        pendingPermission = null
    }

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
        StepApi.setUp(
            flutterEngine.dartExecutor.binaryMessenger,
            StepPlugin(applicationContext) { callback ->
                pendingPermission = callback
                permissionRequest.launch(Manifest.permission.ACTIVITY_RECOGNITION)
            },
        )
        SecurityApi.setUp(flutterEngine.dartExecutor.binaryMessenger, SecurityPlugin { this })
        UsageApi.setUp(flutterEngine.dartExecutor.binaryMessenger, UsagePlugin(applicationContext))
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
