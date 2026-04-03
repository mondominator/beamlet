package com.beamlet.android.data.files

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import com.beamlet.android.data.api.BeamletApiService
import com.beamlet.android.data.api.FileDto
import com.beamlet.android.data.api.PinResponse
import com.beamlet.android.data.auth.AuthRepository
import dagger.hilt.android.qualifiers.ApplicationContext
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.MultipartBody
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.ResponseBody
import okio.BufferedSink
import okio.buffer
import okio.source
import java.io.InputStream
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class FileRepository @Inject constructor(
    private val api: BeamletApiService,
    private val authRepository: AuthRepository,
    @ApplicationContext private val context: Context,
) {
    suspend fun listFiles(limit: Int = 20, offset: Int = 0): List<FileDto> {
        return api.listFiles(limit = limit, offset = offset)
    }

    suspend fun listSentFiles(limit: Int = 20, offset: Int = 0): List<FileDto> {
        return api.listSentFiles(limit = limit, offset = offset)
    }

    suspend fun markRead(fileId: String) {
        api.markRead(fileId)
    }

    suspend fun togglePin(fileId: String): PinResponse {
        return api.togglePin(fileId)
    }

    suspend fun deleteFile(fileId: String) {
        api.deleteFile(fileId)
    }

    suspend fun downloadFile(fileId: String): ResponseBody {
        return api.downloadFile(fileId)
    }

    suspend fun downloadThumbnail(fileId: String): ResponseBody {
        return api.downloadThumbnail(fileId)
    }

    fun thumbnailUrl(fileId: String): String? {
        val serverUrl = authRepository.serverUrl ?: return null
        val base = serverUrl.trimEnd('/')
        return "$base/api/files/$fileId/thumbnail"
    }

    fun authHeaders(): Map<String, String> {
        val headers = mutableMapOf<String, String>()
        authRepository.token?.let { headers["Authorization"] = "Bearer $it" }
        return headers
    }

    suspend fun uploadFile(
        recipientId: String,
        uri: Uri,
        message: String? = null,
        expiryDays: Int? = null,
    ): FileDto {
        val contentResolver = context.contentResolver
        val mimeType = contentResolver.getType(uri) ?: "application/octet-stream"
        val filename = getFilename(uri) ?: "file"

        // Get file size for Content-Length header
        val fileSize = contentResolver.openAssetFileDescriptor(uri, "r")?.use { it.length } ?: -1L

        // Stream from ContentResolver instead of loading entire file into memory
        val requestFile = object : RequestBody() {
            override fun contentType() = mimeType.toMediaTypeOrNull()
            override fun contentLength() = fileSize
            override fun writeTo(sink: BufferedSink) {
                contentResolver.openInputStream(uri)?.use { input ->
                    sink.writeAll(input.source().buffer())
                } ?: throw IllegalStateException("Cannot open input stream for URI: $uri")
            }
        }

        val filePart = MultipartBody.Part.createFormData("file", filename, requestFile)

        val recipientBody = recipientId.toRequestBody("text/plain".toMediaTypeOrNull())

        val messageBody = message?.takeIf { it.isNotBlank() }?.let {
            it.toRequestBody("text/plain".toMediaTypeOrNull())
        }

        val expiryBody = expiryDays?.let {
            it.toString().toRequestBody("text/plain".toMediaTypeOrNull())
        }

        return api.uploadFile(
            recipientId = recipientBody,
            file = filePart,
            message = messageBody,
            expiryDays = expiryBody,
        )
    }

    suspend fun uploadText(
        recipientId: String,
        text: String,
        contentType: String = "text",
    ): FileDto {
        val recipientBody = recipientId.toRequestBody("text/plain".toMediaTypeOrNull())
        val contentTypeBody = contentType.toRequestBody("text/plain".toMediaTypeOrNull())
        val textBody = text.toRequestBody("text/plain".toMediaTypeOrNull())

        return api.uploadText(
            recipientId = recipientBody,
            contentType = contentTypeBody,
            textContent = textBody,
        )
    }

    private fun getFilename(uri: Uri): String? {
        // Try content resolver query first
        context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (nameIndex >= 0 && cursor.moveToFirst()) {
                return cursor.getString(nameIndex)
            }
        }

        // Fall back to URI path
        val path = uri.lastPathSegment
        if (path != null) return path

        // Fall back to MIME type extension
        val mimeType = context.contentResolver.getType(uri)
        val extension = MimeTypeMap.getSingleton().getExtensionFromMimeType(mimeType)
        return "file${extension?.let { ".$it" } ?: ""}"
    }
}
