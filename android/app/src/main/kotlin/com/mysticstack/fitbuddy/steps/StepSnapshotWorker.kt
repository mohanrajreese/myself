package com.mysticstack.fitbuddy.steps

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlinx.coroutines.suspendCancellableCoroutine

/** Fallback when continuous collection is off or stopped (05 §B3). */
class StepSnapshotWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val value = suspendCancellableCoroutine<Long?> { cont -> StepSensor.readOnce(applicationContext) { cont.resume(it) } }
        if (value != null) StepBufferStore(applicationContext).add(applicationContext, value, "worker")
        return Result.success()
    }

    companion object {
        fun schedule(context: Context) {
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                "step-snapshot",
                ExistingPeriodicWorkPolicy.KEEP,
                PeriodicWorkRequestBuilder<StepSnapshotWorker>(15, TimeUnit.MINUTES).build(),
            )
        }
    }
}
