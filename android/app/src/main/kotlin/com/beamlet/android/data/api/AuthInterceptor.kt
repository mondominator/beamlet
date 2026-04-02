package com.beamlet.android.data.api

import com.beamlet.android.data.auth.AuthRepository
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.Interceptor
import okhttp3.Response
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class AuthInterceptor @Inject constructor(
    private val authRepository: AuthRepository,
) : Interceptor {

    override fun intercept(chain: Interceptor.Chain): Response {
        val originalRequest = chain.request()

        // Rewrite the base URL to the configured server
        val serverUrl = authRepository.serverUrl
        val newRequest = if (serverUrl != null) {
            val originalUrl = originalRequest.url
            val newUrl = serverUrl.toHttpUrlOrNull()?.let { baseUrl ->
                originalUrl.newBuilder()
                    .scheme(baseUrl.scheme)
                    .host(baseUrl.host)
                    .port(baseUrl.port)
                    .build()
            } ?: originalUrl

            val builder = originalRequest.newBuilder().url(newUrl)

            // Add auth header
            authRepository.token?.let { token ->
                builder.addHeader("Authorization", "Bearer $token")
            }

            // Add device token header
            authRepository.fcmToken?.let { deviceToken ->
                builder.addHeader("X-Device-Token", deviceToken)
            }

            builder.build()
        } else {
            originalRequest
        }

        val response = chain.proceed(newRequest)

        // Handle 401 by clearing auth state (403 is a permission error, not invalid auth)
        if (response.code == 401) {
            authRepository.clear()
        }

        return response
    }
}
