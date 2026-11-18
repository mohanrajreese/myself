package com.mysticstack.fitbuddy.steps

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat

/** One-shot and continuous access to `TYPE_STEP_COUNTER`. */
object StepSensor {
    fun sensor(context: Context): Sensor? =
        context.getSystemService(SensorManager::class.java)?.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)

    fun hasPermission(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.ACTIVITY_RECOGNITION) ==
            PackageManager.PERMISSION_GRANTED

    /** Registers briefly and returns the first value, or null after [timeoutMs]. */
    fun readOnce(context: Context, timeoutMs: Long = 4000, onResult: (Long?) -> Unit) {
        val manager = context.getSystemService(SensorManager::class.java)
        val sensor = sensor(context)
        if (manager == null || sensor == null || !hasPermission(context)) {
            onResult(null)
            return
        }
        val handler = Handler(Looper.getMainLooper())
        var done = false
        lateinit var listener: SensorEventListener
        val finish = { value: Long? ->
            if (!done) {
                done = true
                manager.unregisterListener(listener)
                onResult(value)
            }
        }
        listener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) = finish(event.values[0].toLong())
            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
        }
        manager.registerListener(listener, sensor, SensorManager.SENSOR_DELAY_NORMAL, 0, handler)
        handler.postDelayed({ finish(null) }, timeoutMs)
    }

    fun prefs(context: Context) = context.getSharedPreferences("fitbuddy_steps", Context.MODE_PRIVATE)

    fun continuousEnabled(context: Context) = prefs(context).getBoolean("continuous", false)
}
