package com.beamlet.android.data.api

import android.text.format.Formatter
import com.google.gson.annotations.SerializedName

data class FileDto(
    @SerializedName("id") val id: String,
    @SerializedName("sender_id") val senderId: String,
    @SerializedName("recipient_id") val recipientId: String,
    @SerializedName("filename") val filename: String,
    @SerializedName("file_type") val fileType: String,
    @SerializedName("file_size") val fileSize: Long,
    @SerializedName("content_type") val contentType: String,
    @SerializedName("text_content") val textContent: String? = null,
    @SerializedName("message") val message: String? = null,
    @SerializedName("read") val read: Boolean,
    @SerializedName("pinned") val pinned: Boolean,
    @SerializedName("expires_at") val expiresAt: java.time.Instant? = null,
    @SerializedName("created_at") val createdAt: java.time.Instant? = null,
    @SerializedName("sender_name") val senderName: String? = null,
    @SerializedName("recipient_name") val recipientName: String? = null,
) {
    val isImage: Boolean get() = fileType.startsWith("image/")
    val isVideo: Boolean get() = fileType.startsWith("video/")
    val isText: Boolean get() = contentType == "text"
    val isLink: Boolean get() = contentType == "link"

    val displayType: String
        get() = when {
            isImage -> "Photo"
            isVideo -> "Video"
            isText -> "Message"
            isLink -> "Link"
            else -> "File"
        }

    fun formattedSize(context: android.content.Context): String {
        return Formatter.formatFileSize(context, fileSize)
    }
}

data class ContactDto(
    @SerializedName("id") val id: String,
    @SerializedName("name") val name: String,
    @SerializedName("created_at") val createdAt: java.time.Instant? = null,
)

data class RegisterDeviceRequest(
    @SerializedName("apns_token") val apnsToken: String,
    @SerializedName("platform") val platform: String = "android",
)

data class RedeemRequest(
    @SerializedName("invite_token") val inviteToken: String,
    @SerializedName("name") val name: String? = null,
)

data class RedeemResponse(
    @SerializedName("user_id") val userId: String?,
    @SerializedName("name") val name: String?,
    @SerializedName("token") val token: String?,
    @SerializedName("contact") val contact: RedeemContact?,
)

data class RedeemContact(
    @SerializedName("id") val id: String,
    @SerializedName("name") val name: String,
)

data class InviteResponse(
    @SerializedName("invite_token") val inviteToken: String,
    @SerializedName("expires_at") val expiresAt: String,
)

data class QrPayload(
    @SerializedName("u") val url: String,
    @SerializedName("i") val invite: String,
)

data class MeResponse(
    @SerializedName("id") val id: String,
    @SerializedName("name") val name: String,
    @SerializedName("files_sent") val filesSent: Int?,
    @SerializedName("files_received") val filesReceived: Int?,
    @SerializedName("storage_used") val storageUsed: Long?,
    @SerializedName("discoverability") val discoverability: String? = null,
)

data class UpdateDiscoverabilityRequest(
    @SerializedName("discoverability") val discoverability: String,
)

data class PinResponse(
    @SerializedName("pinned") val pinned: Boolean,
)
