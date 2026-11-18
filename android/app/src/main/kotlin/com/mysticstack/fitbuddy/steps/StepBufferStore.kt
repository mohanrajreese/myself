package com.mysticstack.fitbuddy.steps

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.os.Build
import android.os.SystemClock
import android.provider.Settings
import java.util.TimeZone

data class BufferedReading(
    val id: Long,
    val cumulativeSteps: Long,
    val bootCount: Long,
    val elapsedRealtimeMs: Long,
    val wallTimeUtcMs: Long,
    val tz: String,
    val utcOffsetS: Long,
    val source: String,
)

/**
 * Raw readings waiting for the app (05 §B3). A plain framework SQLite file:
 * the service and worker write here without a Flutter engine or database key.
 * Holds only step counts and times; excluded from backup.
 */
class StepBufferStore(context: Context) : SQLiteOpenHelper(context, "step_buffer.db", null, 1) {
    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """CREATE TABLE readings (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                steps INTEGER NOT NULL, boot INTEGER NOT NULL, elapsed INTEGER NOT NULL,
                wall INTEGER NOT NULL, tz TEXT NOT NULL, offset INTEGER NOT NULL, source TEXT NOT NULL,
                UNIQUE (boot, elapsed))""",
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit

    fun add(context: Context, steps: Long, source: String): BufferedReading {
        val now = System.currentTimeMillis()
        val zone = TimeZone.getDefault()
        val values = ContentValues().apply {
            put("steps", steps)
            put("boot", bootCount(context))
            put("elapsed", SystemClock.elapsedRealtime())
            put("wall", now)
            put("tz", zone.id)
            put("offset", zone.getOffset(now) / 1000)
            put("source", source)
        }
        val id = writableDatabase.insertWithOnConflict("readings", null, values, SQLiteDatabase.CONFLICT_IGNORE)
        return BufferedReading(
            id, steps, values.getAsLong("boot"), values.getAsLong("elapsed"), now, zone.id,
            values.getAsLong("offset"), source,
        )
    }

    fun pending(): List<BufferedReading> {
        val out = mutableListOf<BufferedReading>()
        readableDatabase.rawQuery("SELECT id, steps, boot, elapsed, wall, tz, offset, source FROM readings ORDER BY id", null)
            .use { c ->
                while (c.moveToNext()) {
                    out.add(
                        BufferedReading(
                            c.getLong(0), c.getLong(1), c.getLong(2), c.getLong(3), c.getLong(4),
                            c.getString(5), c.getLong(6), c.getString(7),
                        ),
                    )
                }
            }
        return out
    }

    fun acknowledge(maxId: Long) {
        writableDatabase.delete("readings", "id <= ?", arrayOf(maxId.toString()))
    }

    companion object {
        /** `Settings.Global.BOOT_COUNT`; changes on every reboot. */
        fun bootCount(context: Context): Long =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                Settings.Global.getLong(context.contentResolver, Settings.Global.BOOT_COUNT, 0)
            } else {
                0
            }
    }
}
