package com.mysticstack.fitbuddy

import android.content.Context
import android.net.Uri
import com.mysticstack.fitbuddy.generated.ExportApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlin.coroutines.resume

/// Saves an export where the user chooses. The app keeps no copy.
class ExportPlugin(
    private val context: Context,
    private val createDocument: (String, (Uri?) -> Unit) -> Unit,
) : ExportApi {
    override suspend fun saveDocument(fileName: String, bytes: ByteArray): Boolean {
        val target = suspendCancellableCoroutine<Uri?> { cont -> createDocument(fileName) { cont.resume(it) } } ?: return false
        return withContext(Dispatchers.IO) {
            runCatching {
                context.contentResolver.openOutputStream(target, "wt")?.use { it.write(bytes) } != null
            }.getOrDefault(false)
        }
    }
}
