package com.beamlet.android.ui.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.beamlet.android.data.auth.AuthRepository
import com.beamlet.android.data.contacts.ContactRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class SettingsUiState(
    val serverUrl: String? = null,
    val fcmToken: String? = null,
    val filesSent: Int? = null,
    val filesReceived: Int? = null,
    val storageUsed: Long? = null,
    val appTheme: String = "system",
    val fileExpiryDays: Int = 1,
    val showDisconnectDialog: Boolean = false,
)

@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val authRepository: AuthRepository,
    private val contactRepository: ContactRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow(SettingsUiState())
    val uiState: StateFlow<SettingsUiState> = _uiState.asStateFlow()

    init {
        _uiState.value = _uiState.value.copy(
            serverUrl = authRepository.serverUrl,
            fcmToken = authRepository.fcmToken,
        )
        loadStats()
    }

    private fun loadStats() {
        viewModelScope.launch {
            try {
                val me = contactRepository.getMe()
                _uiState.value = _uiState.value.copy(
                    filesSent = me.filesSent,
                    filesReceived = me.filesReceived,
                    storageUsed = me.storageUsed,
                )
            } catch (_: Exception) { }
        }
    }

    fun setAppTheme(theme: String) {
        _uiState.value = _uiState.value.copy(appTheme = theme)
    }

    fun setFileExpiryDays(days: Int) {
        _uiState.value = _uiState.value.copy(fileExpiryDays = days)
    }

    fun showDisconnectDialog() {
        _uiState.value = _uiState.value.copy(showDisconnectDialog = true)
    }

    fun dismissDisconnectDialog() {
        _uiState.value = _uiState.value.copy(showDisconnectDialog = false)
    }

    fun disconnect() {
        authRepository.clear()
        _uiState.value = _uiState.value.copy(showDisconnectDialog = false)
    }

    fun formatBytes(bytes: Long): String {
        return when {
            bytes < 1024 -> "$bytes B"
            bytes < 1024 * 1024 -> "${bytes / 1024} KB"
            bytes < 1024 * 1024 * 1024 -> String.format("%.1f MB", bytes / (1024.0 * 1024.0))
            else -> String.format("%.1f GB", bytes / (1024.0 * 1024.0 * 1024.0))
        }
    }
}
