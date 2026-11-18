package com.mysticstack.fitbuddy.steps

import android.content.Context
import com.mysticstack.fitbuddy.generated.StepApi
import com.mysticstack.fitbuddy.generated.StepReadingMessage
import kotlin.coroutines.resume
import kotlinx.coroutines.suspendCancellableCoroutine

class StepPlugin(
    private val context: Context,
    private val requestActivityPermission: ((Boolean) -> Unit) -> Unit,
) : StepApi {
    private val buffer by lazy { StepBufferStore(context) }

    override fun hasSensor(): Boolean = StepSensor.sensor(context) != null

    override fun hasPermission(): Boolean = StepSensor.hasPermission(context)

    override suspend fun requestPermission(): Boolean =
        if (hasPermission()) true else suspendCancellableCoroutine { cont -> requestActivityPermission { cont.resume(it) } }

    override suspend fun readNow(): StepReadingMessage? {
        val value = suspendCancellableCoroutine<Long?> { cont -> StepSensor.readOnce(context) { cont.resume(it) } } ?: return null
        return message(buffer.add(context, value, "foreground"))
    }

    override fun pendingReadings(): List<StepReadingMessage> = buffer.pending().map(::message)

    override fun acknowledge(maxId: Long) = buffer.acknowledge(maxId)

    override fun setContinuous(enabled: Boolean) {
        StepSensor.prefs(context).edit().putBoolean("continuous", enabled).apply()
        if (enabled) StepCollectionService.start(context) else StepCollectionService.stop(context)
    }

    override fun isContinuous(): Boolean = StepSensor.continuousEnabled(context)

    override fun scheduleSnapshots() = StepSnapshotWorker.schedule(context)

    private fun message(r: BufferedReading) = StepReadingMessage(
        r.id, r.cumulativeSteps, r.bootCount, r.elapsedRealtimeMs, r.wallTimeUtcMs, r.tz, r.utcOffsetS, r.source,
    )
}
