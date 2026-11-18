package com.mysticstack.fitbuddy

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.mysticstack.fitbuddy.steps.StepBufferStore
import com.mysticstack.fitbuddy.steps.StepCollectionService
import com.mysticstack.fitbuddy.steps.StepSensor

/**
 * Records that a system event happened while the app may be closed. Dart
 * reads and clears it at the next start or top-up run and re-plans reminders.
 * No database access here (rules: Kotlin stays thin).
 */
class SystemEventReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val event = eventFor(intent.action) ?: return
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(KEY, event).apply()
        // Steps: a reading at boot marks the new boot session; restart
        // continuous collection if the user turned it on (05 §B3).
        if (event == "boot" || event == "update") {
            val pending = goAsync()
            StepSensor.readOnce(context) { value ->
                if (value != null) StepBufferStore(context).add(context, value, "boot")
                if (StepSensor.continuousEnabled(context)) StepCollectionService.start(context)
                pending.finish()
            }
        }
    }

    companion object {
        const val PREFS = "fitbuddy_system_events"
        const val KEY = "pending"

        fun eventFor(action: String?): String? = when (action) {
            Intent.ACTION_BOOT_COMPLETED -> "boot"
            Intent.ACTION_MY_PACKAGE_REPLACED -> "update"
            Intent.ACTION_TIMEZONE_CHANGED -> "timezone"
            Intent.ACTION_TIME_CHANGED -> "time"
            "android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED" -> "exact_alarm"
            else -> null
        }
    }
}
