package com.beamlet.android.ui.inbox

import android.content.Context
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ProcessLifecycleOwner
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.beamlet.android.data.api.FileDto
import com.beamlet.android.data.files.FileRepository
import com.beamlet.android.ui.settings.SettingsViewModel
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.temporal.ChronoUnit
import javax.inject.Inject

data class InboxUiState(
    val receivedFiles: List<FileDto> = emptyList(),
    val sentFiles: List<FileDto> = emptyList(),
    val isLoadingReceived: Boolean = true,
    val isLoadingSent: Boolean = false,
    val error: String? = null,
    val selectedTab: InboxTab = InboxTab.RECEIVED,
    val isRefreshing: Boolean = false,
)

enum class InboxTab { RECEIVED, SENT }

@HiltViewModel
class InboxViewModel @Inject constructor(
    private val fileRepository: FileRepository,
    @ApplicationContext private val context: Context,
) : ViewModel() {

    private val prefs = context.getSharedPreferences("beamlet_prefs", Context.MODE_PRIVATE)

    private val _uiState = MutableStateFlow(InboxUiState())
    val uiState: StateFlow<InboxUiState> = _uiState.asStateFlow()

    init {
        loadReceivedFiles()
        startPolling()
    }

    fun selectTab(tab: InboxTab) {
        _uiState.value = _uiState.value.copy(selectedTab = tab)
        if (tab == InboxTab.SENT && _uiState.value.sentFiles.isEmpty()) {
            loadSentFiles()
        }
    }

    fun loadReceivedFiles() {
        viewModelScope.launch {
            try {
                val files = fileRepository.listFiles()
                val filtered = cleanupOldFiles(files)
                _uiState.value = _uiState.value.copy(
                    receivedFiles = filtered,
                    isLoadingReceived = false,
                    isRefreshing = false,
                    error = null,
                )
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(
                    isLoadingReceived = false,
                    isRefreshing = false,
                    error = e.message,
                )
            }
        }
    }

    /**
     * Auto-delete received files older than the user's cleanup preference.
     * Pinned files are preserved. Deletes happen in the background.
     */
    private fun cleanupOldFiles(files: List<FileDto>): List<FileDto> {
        val expiryDays = prefs.getInt(SettingsViewModel.PREF_INBOX_CLEANUP_DAYS, 1)
        if (expiryDays <= 0) return files

        val cutoff = Instant.now().minus(expiryDays.toLong(), ChronoUnit.DAYS)
        val expiredIds = mutableSetOf<String>()

        for (file in files) {
            if (file.pinned) continue
            val created = file.createdAt ?: continue
            if (created.isBefore(cutoff)) {
                expiredIds.add(file.id)
            }
        }

        if (expiredIds.isNotEmpty()) {
            viewModelScope.launch {
                for (id in expiredIds) {
                    try { fileRepository.deleteFile(id) } catch (_: Exception) { }
                }
            }
        }

        return files.filter { it.id !in expiredIds }
    }

    fun loadSentFiles() {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoadingSent = true)
            try {
                val files = fileRepository.listSentFiles()
                _uiState.value = _uiState.value.copy(
                    sentFiles = files,
                    isLoadingSent = false,
                )
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(isLoadingSent = false)
            }
        }
    }

    fun refresh() {
        _uiState.value = _uiState.value.copy(isRefreshing = true)
        if (_uiState.value.selectedTab == InboxTab.RECEIVED) {
            loadReceivedFiles()
        } else {
            loadSentFiles()
            _uiState.value = _uiState.value.copy(isRefreshing = false)
        }
    }

    fun markRead(fileId: String) {
        viewModelScope.launch {
            try {
                fileRepository.markRead(fileId)
                // Update local state
                _uiState.value = _uiState.value.copy(
                    receivedFiles = _uiState.value.receivedFiles.map { file ->
                        if (file.id == fileId) file.copy(read = true) else file
                    }
                )
            } catch (_: Exception) { }
        }
    }

    fun togglePin(fileId: String) {
        viewModelScope.launch {
            try {
                val response = fileRepository.togglePin(fileId)
                _uiState.value = _uiState.value.copy(
                    receivedFiles = _uiState.value.receivedFiles.map { file ->
                        if (file.id == fileId) file.copy(pinned = response.pinned) else file
                    }
                )
            } catch (_: Exception) { }
        }
    }

    fun deleteFile(fileId: String) {
        viewModelScope.launch {
            // Optimistically remove
            _uiState.value = _uiState.value.copy(
                receivedFiles = _uiState.value.receivedFiles.filter { it.id != fileId }
            )
            try {
                fileRepository.deleteFile(fileId)
            } catch (_: Exception) {
                // Reload on failure
                loadReceivedFiles()
            }
        }
    }

    fun thumbnailUrl(fileId: String): String? {
        return fileRepository.thumbnailUrl(fileId)
    }

    fun authHeaders(): Map<String, String> {
        return fileRepository.authHeaders()
    }

    private fun startPolling() {
        viewModelScope.launch {
            while (isActive) {
                delay(10_000)
                // Only poll when the app is in the foreground
                if (!ProcessLifecycleOwner.get().lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)) {
                    continue
                }
                try {
                    val files = fileRepository.listFiles()
                    val filtered = cleanupOldFiles(files)
                    _uiState.value = _uiState.value.copy(receivedFiles = filtered)
                    // Also refresh sent if on that tab
                    if (_uiState.value.selectedTab == InboxTab.SENT) {
                        val sentFiles = fileRepository.listSentFiles()
                        _uiState.value = _uiState.value.copy(sentFiles = sentFiles)
                    }
                } catch (_: Exception) { }
            }
        }
    }
}
