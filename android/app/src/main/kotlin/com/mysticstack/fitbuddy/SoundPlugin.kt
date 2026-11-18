package com.mysticstack.fitbuddy

import android.content.Context
import android.content.Intent
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import com.mysticstack.fitbuddy.generated.SoundApi
import com.mysticstack.fitbuddy.generated.SystemSound
import java.io.File
import kotlin.coroutines.resume
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext

/** System sounds, custom sound files and previews (§5.15F). */
class SoundPlugin(
    private val context: Context,
    /** Starts the system document picker; calls back with the chosen URI or null. */
    private val pickDocument: ((Uri?) -> Unit) -> Unit,
) : SoundApi {
    private var preview: Ringtone? = null

    override fun systemSounds(): List<SystemSound> {
        val manager = RingtoneManager(context).apply { setType(RingtoneManager.TYPE_NOTIFICATION) }
        val out = mutableListOf<SystemSound>()
        manager.cursor.use { cursor ->
            while (cursor.moveToNext()) {
                val title = cursor.getString(RingtoneManager.TITLE_COLUMN_INDEX) ?: continue
                out.add(SystemSound(title, manager.getRingtoneUri(cursor.position).toString()))
            }
        }
        return out
    }

    override suspend fun pickAndImportSound(): String? {
        val picked = suspendCancellableCoroutine<Uri?> { cont -> pickDocument { uri -> cont.resume(uri) } } ?: return null
        return withContext(Dispatchers.IO) { runCatching { import(picked) }.getOrNull() }
    }

    private fun import(source: Uri): String? {
        val name = displayName(source) ?: "sound"
        val dir = File(context.filesDir, "sounds").apply { mkdirs() }
        val target = File(dir, safeName(name, name.substringAfterLast('.', "")))
        context.contentResolver.openInputStream(source)?.use { input ->
            target.outputStream().use { output -> input.copyTo(output) }
        } ?: return null
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.sounds", target)
        // The notification system plays the sound from its own process.
        context.grantUriPermission("com.android.systemui", uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        return uri.toString()
    }

    private fun displayName(uri: Uri): String? =
        context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) c.getString(0) else null
        }

    override fun play(uri: String) {
        stop()
        preview = RingtoneManager.getRingtone(context, Uri.parse(uri))?.also { it.play() }
    }

    override fun stop() {
        preview?.stop()
        preview = null
    }

    companion object {
        /** Letters, digits, dash and underscore only, so the URI is predictable. */
        fun safeName(name: String, extension: String): String {
            val base = name.substringBeforeLast('.').replace(Regex("[^A-Za-z0-9_-]"), "_").take(40).ifEmpty { "sound" }
            val ext = extension.lowercase().replace(Regex("[^a-z0-9]"), "").take(5).ifEmpty { "ogg" }
            return "$base.$ext"
        }
    }
}
