package com.mysticstack.fitbuddy

import android.app.Activity
import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Process
import android.provider.Settings
import android.view.WindowManager
import com.mysticstack.fitbuddy.generated.AppUsageMessage
import com.mysticstack.fitbuddy.generated.SecurityApi
import com.mysticstack.fitbuddy.generated.UsageApi

class SecurityPlugin(private val activity: () -> Activity?) : SecurityApi {
    override fun setSecureWindow(secure: Boolean) {
        val window = activity()?.window ?: return
        if (secure) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }
}

/**
 * Screen time from usage events (§5.17, R-13): foreground time is summed
 * between "resumed" and "paused/stopped" events of each app. Raw facts only;
 * reports are computed in Dart. Nothing here leaves the phone.
 */
class UsagePlugin(private val context: Context) : UsageApi {
    override fun hasAccess(): Boolean {
        val ops = context.getSystemService(AppOpsManager::class.java)
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName)
        } else {
            @Suppress("DEPRECATION")
            ops.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName)
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    override fun openAccessSettings() {
        context.startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    override fun usage(startMs: Long, endMs: Long): List<AppUsageMessage> {
        if (!hasAccess()) return emptyList()
        val manager = context.getSystemService(UsageStatsManager::class.java)
        val events = manager.queryEvents(startMs, endMs)
        val openSince = HashMap<String, Long>()
        val totals = HashMap<String, Long>()
        val event = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            val pkg = event.packageName ?: continue
            when (event.eventType) {
                UsageEvents.Event.ACTIVITY_RESUMED -> openSince.putIfAbsent(pkg, event.timeStamp)
                UsageEvents.Event.ACTIVITY_PAUSED, UsageEvents.Event.ACTIVITY_STOPPED -> {
                    val from = openSince.remove(pkg) ?: continue
                    totals[pkg] = (totals[pkg] ?: 0) + (event.timeStamp - from)
                }
            }
        }
        // Still open at the end of the range.
        for ((pkg, from) in openSince) totals[pkg] = (totals[pkg] ?: 0) + (endMs - from)
        val pm = context.packageManager
        return totals.filter { it.value > 0 && it.key != context.packageName }.map { (pkg, ms) ->
            val label = runCatching { pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString() }.getOrDefault(pkg)
            AppUsageMessage(pkg, label, ms)
        }
    }
}
