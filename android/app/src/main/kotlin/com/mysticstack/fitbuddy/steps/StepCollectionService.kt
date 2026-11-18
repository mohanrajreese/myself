package com.mysticstack.fitbuddy.steps

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import com.mysticstack.fitbuddy.MainActivity
import com.mysticstack.fitbuddy.R
import java.util.Calendar

/**
 * Opt-in continuous collection (05 §B3): keeps a step listener registered
 * and writes a reading every 5 minutes when steps changed, at midnight, on
 * shutdown, and on timezone or clock change. Kotlin stays thin: no totals here.
 */
class StepCollectionService : Service(), SensorEventListener {
    private var lastStored: Long = -1
    private var lastStoredAt: Long = 0
    private var latest: Long = -1
    private lateinit var buffer: StepBufferStore

    private val events = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val source = when (intent.action) {
                Intent.ACTION_SHUTDOWN -> "shutdown"
                ACTION_MIDNIGHT -> "service"
                else -> "time_change"
            }
            store(source, force = true)
            if (intent.action == ACTION_MIDNIGHT) scheduleMidnight()
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        buffer = StepBufferStore(this)
        createChannel()
        val notification = NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(getString(R.string.step_service_title))
            .setContentText(getString(R.string.step_service_text))
            .setOngoing(true)
            .setSilent(true)
            .setContentIntent(
                PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE),
            )
            .build()
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH
        } else {
            0
        }
        ServiceCompat.startForeground(this, NOTIFICATION_ID, notification, type)
        val sensor = StepSensor.sensor(this)
        if (sensor == null || !StepSensor.hasPermission(this)) {
            stopSelf()
            return
        }
        // Batch delivery up to 5 minutes to save power.
        getSystemService(SensorManager::class.java)
            .registerListener(this, sensor, SensorManager.SENSOR_DELAY_NORMAL, 5 * 60 * 1_000_000)
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SHUTDOWN)
            addAction(Intent.ACTION_TIMEZONE_CHANGED)
            addAction(Intent.ACTION_TIME_CHANGED)
            addAction(ACTION_MIDNIGHT)
        }
        ContextCompat.registerReceiver(this, events, filter, ContextCompat.RECEIVER_NOT_EXPORTED)
        scheduleMidnight()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_STICKY

    override fun onDestroy() {
        store("service", force = true)
        getSystemService(SensorManager::class.java).unregisterListener(this)
        runCatching { unregisterReceiver(events) }
        super.onDestroy()
    }

    override fun onSensorChanged(event: SensorEvent) {
        latest = event.values[0].toLong()
        store("service", force = false)
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    private fun store(source: String, force: Boolean) {
        if (latest < 0) return
        val now = System.currentTimeMillis()
        if (!force && (latest == lastStored || now - lastStoredAt < 5 * 60 * 1000)) return
        buffer.add(this, latest, source)
        lastStored = latest
        lastStoredAt = now
    }

    private fun scheduleMidnight() {
        val next = Calendar.getInstance().apply {
            add(Calendar.DAY_OF_YEAR, 1)
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 5)
        }
        val intent = PendingIntent.getBroadcast(
            this, 1, Intent(ACTION_MIDNIGHT).setPackage(packageName),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        // Inexact is enough: a late flush only widens the midnight split.
        getSystemService(AlarmManager::class.java).setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next.timeInMillis, intent)
    }

    private fun createChannel() {
        val channel = NotificationChannel(CHANNEL, getString(R.string.step_channel_name), NotificationManager.IMPORTANCE_MIN)
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    companion object {
        const val CHANNEL = "steps_service_v1"
        const val NOTIFICATION_ID = 901
        const val ACTION_MIDNIGHT = "com.mysticstack.fitbuddy.STEP_MIDNIGHT"

        /** Starts only when allowed: permission granted, from the foreground or boot. */
        fun start(context: Context): Boolean {
            if (StepSensor.sensor(context) == null || !StepSensor.hasPermission(context)) return false
            return runCatching {
                ContextCompat.startForegroundService(context, Intent(context, StepCollectionService::class.java))
            }.isSuccess
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, StepCollectionService::class.java))
        }
    }
}
