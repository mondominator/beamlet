package com.beamlet.android.data.api

import okhttp3.MultipartBody
import okhttp3.RequestBody
import okhttp3.ResponseBody
import retrofit2.Response
import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.Multipart
import retrofit2.http.POST
import retrofit2.http.PUT
import retrofit2.http.Part
import retrofit2.http.Path
import retrofit2.http.Query
import retrofit2.http.Streaming

interface BeamletApiService {

    // --- Users / Contacts ---

    @GET("api/contacts")
    suspend fun listContacts(): List<ContactDto>

    @DELETE("api/contacts/{id}")
    suspend fun deleteContact(@Path("id") contactId: String): Response<Unit>

    // --- Device Registration ---

    @POST("api/auth/register-device")
    suspend fun registerDevice(@Body request: RegisterDeviceRequest): Response<Unit>

    // --- Files ---

    @GET("api/files")
    suspend fun listFiles(
        @Query("limit") limit: Int = 20,
        @Query("offset") offset: Int = 0,
    ): List<FileDto>

    @GET("api/files/sent")
    suspend fun listSentFiles(
        @Query("limit") limit: Int = 20,
        @Query("offset") offset: Int = 0,
    ): List<FileDto>

    @PUT("api/files/{id}/read")
    suspend fun markRead(@Path("id") fileId: String): Response<Unit>

    @PUT("api/files/{id}/pin")
    suspend fun togglePin(@Path("id") fileId: String): PinResponse

    @DELETE("api/files/{id}")
    suspend fun deleteFile(@Path("id") fileId: String): Response<Unit>

    @Streaming
    @GET("api/files/{id}")
    suspend fun downloadFile(@Path("id") fileId: String): ResponseBody

    @GET("api/files/{id}/thumbnail")
    suspend fun downloadThumbnail(@Path("id") fileId: String): ResponseBody

    // --- Upload (multipart) ---

    @Multipart
    @POST("api/files")
    suspend fun uploadFile(
        @Part("recipient_id") recipientId: RequestBody,
        @Part file: MultipartBody.Part,
        @Part("message") message: RequestBody? = null,
        @Part("expiry_days") expiryDays: RequestBody? = null,
    ): FileDto

    @Multipart
    @POST("api/files")
    suspend fun uploadText(
        @Part("recipient_id") recipientId: RequestBody,
        @Part("content_type") contentType: RequestBody,
        @Part("text_content") textContent: RequestBody,
    ): FileDto

    // --- Invites ---

    @POST("api/invites")
    suspend fun createInvite(): InviteResponse

    @POST("api/invites/redeem")
    suspend fun redeemInvite(@Body request: RedeemRequest): RedeemResponse

    // --- Profile ---

    @GET("api/me")
    suspend fun getMe(): MeResponse

    @PUT("api/me/discoverability")
    suspend fun updateDiscoverability(@Body request: UpdateDiscoverabilityRequest): Response<Unit>

    @GET("api/users/{id}/profile")
    suspend fun getProfile(@Path("id") userId: String): MeResponse
}
