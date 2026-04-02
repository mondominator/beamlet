package com.beamlet.android.ui.setup

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.beamlet.android.data.api.QrPayload
import com.beamlet.android.data.auth.AuthRepository
import com.beamlet.android.data.contacts.ContactRepository
import com.google.gson.Gson
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class SetupUiState(
    val serverUrl: String = "",
    val token: String = "",
    val isConnecting: Boolean = false,
    val error: String? = null,
    val scannedPayload: QrPayload? = null,
    val showNameEntry: Boolean = false,
    val nameText: String = "",
    val isRedeemingInvite: Boolean = false,
)

@HiltViewModel
class SetupViewModel @Inject constructor(
    private val authRepository: AuthRepository,
    private val contactRepository: ContactRepository,
    private val gson: Gson,
) : ViewModel() {

    private val _uiState = MutableStateFlow(SetupUiState())
    val uiState: StateFlow<SetupUiState> = _uiState.asStateFlow()

    fun updateServerUrl(value: String) {
        _uiState.value = _uiState.value.copy(serverUrl = value, error = null)
    }

    fun updateToken(value: String) {
        _uiState.value = _uiState.value.copy(token = value, error = null)
    }

    fun updateName(value: String) {
        _uiState.value = _uiState.value.copy(nameText = value)
    }

    fun dismissNameEntry() {
        _uiState.value = _uiState.value.copy(
            showNameEntry = false,
            scannedPayload = null,
            nameText = "",
        )
    }

    fun handleQrScan(rawValue: String) {
        try {
            val payload = gson.fromJson(rawValue, QrPayload::class.java)
            if (payload.url.isNotBlank() && payload.invite.isNotBlank()) {
                _uiState.value = _uiState.value.copy(
                    scannedPayload = payload,
                    showNameEntry = true,
                )
            } else {
                _uiState.value = _uiState.value.copy(error = "Invalid QR code")
            }
        } catch (e: Exception) {
            _uiState.value = _uiState.value.copy(error = "Invalid QR code")
        }
    }

    fun handleDeepLink(serverUrl: String, inviteToken: String) {
        val payload = QrPayload(url = serverUrl, invite = inviteToken)
        _uiState.value = _uiState.value.copy(
            scannedPayload = payload,
            showNameEntry = true,
        )
    }

    fun redeemInvite() {
        val state = _uiState.value
        val payload = state.scannedPayload ?: return
        val name = state.nameText.trim()
        if (name.isBlank()) {
            _uiState.value = state.copy(error = "Please enter your name")
            return
        }

        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isRedeemingInvite = true, error = null)
            try {
                val response = contactRepository.redeemInvite(
                    serverUrl = payload.url,
                    inviteToken = payload.invite,
                    name = name,
                )

                val token = response.token
                val userId = response.userId
                if (token != null) {
                    authRepository.store(serverUrl = payload.url, token = token)
                    if (userId != null) {
                        authRepository.storeUserId(userId)
                    }
                    _uiState.value = _uiState.value.copy(
                        isRedeemingInvite = false,
                        showNameEntry = false,
                        scannedPayload = null,
                    )
                } else {
                    _uiState.value = _uiState.value.copy(
                        isRedeemingInvite = false,
                        error = "Server did not return a token",
                    )
                }
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(
                    isRedeemingInvite = false,
                    error = e.message ?: "Failed to redeem invite",
                )
            }
        }
    }

    fun connectManually() {
        val state = _uiState.value
        val url = state.serverUrl.trim()
        val token = state.token.trim()

        if (url.isBlank() || token.isBlank()) return

        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isConnecting = true, error = null)
            try {
                // Validate by trying to call getMe
                // First store credentials so the AuthInterceptor can use them
                authRepository.store(serverUrl = url, token = token)

                val me = contactRepository.getMe()
                authRepository.storeUserId(me.id)

                _uiState.value = _uiState.value.copy(isConnecting = false)
            } catch (e: Exception) {
                // Auth failed — clear stored credentials
                authRepository.clear()
                _uiState.value = _uiState.value.copy(
                    isConnecting = false,
                    error = "Could not connect. Check URL and token.",
                )
            }
        }
    }
}
