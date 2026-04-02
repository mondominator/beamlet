package com.beamlet.android.data.auth

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject
import javax.inject.Singleton

sealed class AuthState {
    data object Unauthenticated : AuthState()
    data class Authenticated(
        val serverUrl: String,
        val token: String,
        val userId: String?,
    ) : AuthState()
}

@Singleton
class AuthRepository @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    private val masterKey = MasterKey.Builder(context)
        .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
        .build()

    private val prefs: SharedPreferences = EncryptedSharedPreferences.create(
        context,
        PREFS_NAME,
        masterKey,
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
    )

    private val _authState = MutableStateFlow<AuthState>(loadInitialState())
    val authState: StateFlow<AuthState> = _authState.asStateFlow()

    val isAuthenticated: Boolean
        get() = _authState.value is AuthState.Authenticated

    val serverUrl: String?
        get() = prefs.getString(KEY_SERVER_URL, null)

    val token: String?
        get() = prefs.getString(KEY_TOKEN, null)

    val userId: String?
        get() = prefs.getString(KEY_USER_ID, null)

    val fcmToken: String?
        get() = prefs.getString(KEY_FCM_TOKEN, null)

    private fun loadInitialState(): AuthState {
        val serverUrl = prefs.getString(KEY_SERVER_URL, null)
        val token = prefs.getString(KEY_TOKEN, null)
        return if (serverUrl != null && token != null) {
            AuthState.Authenticated(
                serverUrl = serverUrl,
                token = token,
                userId = prefs.getString(KEY_USER_ID, null),
            )
        } else {
            AuthState.Unauthenticated
        }
    }

    fun store(serverUrl: String, token: String) {
        prefs.edit()
            .putString(KEY_SERVER_URL, serverUrl)
            .putString(KEY_TOKEN, token)
            .apply()
        _authState.value = AuthState.Authenticated(
            serverUrl = serverUrl,
            token = token,
            userId = prefs.getString(KEY_USER_ID, null),
        )
    }

    fun storeUserId(userId: String) {
        prefs.edit()
            .putString(KEY_USER_ID, userId)
            .apply()
        val current = _authState.value
        if (current is AuthState.Authenticated) {
            _authState.value = current.copy(userId = userId)
        }
    }

    fun storeFcmToken(fcmToken: String) {
        prefs.edit()
            .putString(KEY_FCM_TOKEN, fcmToken)
            .apply()
    }

    fun clear() {
        prefs.edit().clear().apply()
        _authState.value = AuthState.Unauthenticated
    }

    companion object {
        private const val PREFS_NAME = "beamlet_secure_prefs"
        private const val KEY_SERVER_URL = "server_url"
        private const val KEY_TOKEN = "auth_token"
        private const val KEY_USER_ID = "user_id"
        private const val KEY_FCM_TOKEN = "fcm_token"
    }
}
