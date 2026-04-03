package com.beamlet.android.ui.settings

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.beamlet.android.data.auth.AuthRepository
import com.beamlet.android.data.contacts.ContactRepository
import com.beamlet.android.data.nearby.DiscoverabilityMode
import com.beamlet.android.data.nearby.NearbyService
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
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
    val fileExpiryDays: Int = 7,
    val inboxCleanupDays: Int = 1,
    val showDisconnectDialog: Boolean = false,
    val discoverabilityMode: DiscoverabilityMode = DiscoverabilityMode.CONTACTS_ONLY,
)

@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val authRepository: AuthRepository,
    private val contactRepository: ContactRepository,
    private val nearbyService: NearbyService,
    @ApplicationContext private val context: Context,
) : ViewModel() {

    private val prefs = context.getSharedPreferences("beamlet_prefs", Context.MODE_PRIVATE)

    private val _uiState = MutableStateFlow(SettingsUiState())
    val uiState: StateFlow<SettingsUiState> = _uiState.asStateFlow()

    init {
        val savedExpiry = prefs.getInt(PREF_FILE_EXPIRY_DAYS, 7)
        val savedCleanup = prefs.getInt(PREF_INBOX_CLEANUP_DAYS, 1)
        _uiState.value = _uiState.value.copy(
            serverUrl = authRepository.serverUrl,
            fcmToken = authRepository.fcmToken,
            fileExpiryDays = savedExpiry,
            inboxCleanupDays = savedCleanup,
        )
        loadStats()
        viewModelScope.launch {
            nearbyService.mode.collect { mode ->
                _uiState.value = _uiState.value.copy(discoverabilityMode = mode)
            }
        }
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

    fun setDiscoverabilityMode(mode: DiscoverabilityMode) {
        nearbyService.setMode(mode)
    }

    fun setAppTheme(theme: String) {
        _uiState.value = _uiState.value.copy(appTheme = theme)
    }

    fun setFileExpiryDays(days: Int) {
        _uiState.value = _uiState.value.copy(fileExpiryDays = days)
        prefs.edit().putInt(PREF_FILE_EXPIRY_DAYS, days).apply()
    }

    fun setInboxCleanupDays(days: Int) {
        _uiState.value = _uiState.value.copy(inboxCleanupDays = days)
        prefs.edit().putInt(PREF_INBOX_CLEANUP_DAYS, days).apply()
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

    companion object {
        const val PREF_FILE_EXPIRY_DAYS = "file_expiry_days"
        const val PREF_INBOX_CLEANUP_DAYS = "inbox_cleanup_days"
    }
}
