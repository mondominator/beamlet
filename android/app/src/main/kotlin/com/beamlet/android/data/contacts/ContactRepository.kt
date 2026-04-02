package com.beamlet.android.data.contacts

import com.beamlet.android.data.api.BeamletApiService
import com.beamlet.android.data.api.ContactDto
import com.beamlet.android.data.api.InviteResponse
import com.beamlet.android.data.api.MeResponse
import com.beamlet.android.data.api.RedeemRequest
import com.beamlet.android.data.api.RedeemResponse
import com.beamlet.android.data.auth.AuthRepository
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import com.google.gson.Gson
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class ContactRepository @Inject constructor(
    private val api: BeamletApiService,
    private val authRepository: AuthRepository,
    private val okHttpClient: OkHttpClient,
    private val gson: Gson,
) {
    suspend fun listContacts(): List<ContactDto> {
        return api.listContacts()
    }

    suspend fun deleteContact(contactId: String) {
        api.deleteContact(contactId)
    }

    suspend fun createInvite(): InviteResponse {
        return api.createInvite()
    }

    /**
     * Redeem an invite as a new user (no auth required).
     * This bypasses the AuthInterceptor since it needs to hit a specific server URL
     * before the user is authenticated.
     */
    suspend fun redeemInvite(
        serverUrl: String,
        inviteToken: String,
        name: String,
    ): RedeemResponse = withContext(Dispatchers.IO) {
        val baseUrl = serverUrl.trimEnd('/')
        val url = "$baseUrl/api/invites/redeem"

        val body = gson.toJson(RedeemRequest(inviteToken = inviteToken, name = name))
        val requestBody = body.toRequestBody("application/json".toMediaTypeOrNull())

        val request = Request.Builder()
            .url(url)
            .post(requestBody)
            .build()

        val response = okHttpClient.newBuilder()
            .build()
            .newCall(request)
            .execute()

        if (!response.isSuccessful) {
            val errorBody = response.body?.string()
            throw RuntimeException("Redeem failed (${response.code}): $errorBody")
        }

        val responseBody = response.body?.string()
            ?: throw RuntimeException("Empty response body")

        gson.fromJson(responseBody, RedeemResponse::class.java)
    }

    /**
     * Redeem an invite as an existing authenticated user.
     * Uses the normal authenticated API path.
     */
    suspend fun redeemInviteAsExistingUser(inviteToken: String): RedeemResponse {
        return api.redeemInvite(RedeemRequest(inviteToken = inviteToken))
    }

    suspend fun getMe(): MeResponse {
        return api.getMe()
    }

    suspend fun getProfile(userId: String): MeResponse {
        return api.getProfile(userId)
    }

    suspend fun registerDevice(fcmToken: String) {
        val request = com.beamlet.android.data.api.RegisterDeviceRequest(
            apnsToken = fcmToken,
            platform = "android",
        )
        api.registerDevice(request)
    }
}
