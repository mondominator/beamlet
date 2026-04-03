package com.beamlet.android.shareactivity

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.beamlet.android.data.api.ContactDto
import com.beamlet.android.data.contacts.ContactRepository
import com.beamlet.android.data.files.FileRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class ShareUiState(
    val uri: Uri? = null,
    val displayName: String? = null,
    val contacts: List<ContactDto> = emptyList(),
    val selectedUserIds: Set<String> = emptySet(),
    val isLoadingContacts: Boolean = true,
    val isSending: Boolean = false,
    val error: String? = null,
    val sendComplete: Boolean = false,
)

@HiltViewModel
class ShareViewModel @Inject constructor(
    private val contactRepository: ContactRepository,
    private val fileRepository: FileRepository,
    @ApplicationContext private val context: Context,
) : ViewModel() {

    private val _uiState = MutableStateFlow(ShareUiState())
    val uiState: StateFlow<ShareUiState> = _uiState.asStateFlow()

    init {
        loadContacts()
    }

    fun processIntent(intent: Intent) {
        val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            ?: intent.data
        if (uri != null) {
            val name = getDisplayName(uri)
            _uiState.value = _uiState.value.copy(
                uri = uri,
                displayName = name ?: "Shared file",
            )
        } else {
            // Handle text share
            val text = intent.getStringExtra(Intent.EXTRA_TEXT)
            if (text != null) {
                // For text shares, we'd need a different upload path.
                // For now, set a display name
                _uiState.value = _uiState.value.copy(
                    displayName = "Shared text",
                    error = "Text sharing not yet supported. Please share a file instead.",
                )
            }
        }
    }

    private fun loadContacts() {
        viewModelScope.launch {
            try {
                val contacts = contactRepository.listContacts()
                _uiState.value = _uiState.value.copy(
                    contacts = contacts,
                    isLoadingContacts = false,
                )
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(
                    isLoadingContacts = false,
                    error = "Failed to load contacts",
                )
            }
        }
    }

    fun toggleUser(userId: String) {
        val current = _uiState.value.selectedUserIds
        _uiState.value = _uiState.value.copy(
            selectedUserIds = if (current.contains(userId)) current - userId else current + userId
        )
    }

    fun isSelected(userId: String): Boolean {
        return _uiState.value.selectedUserIds.contains(userId)
    }

    fun send() {
        val state = _uiState.value
        val uri = state.uri ?: return
        if (state.selectedUserIds.isEmpty()) return

        // Check file size before loading into memory
        val fileSize = try {
            context.contentResolver.openAssetFileDescriptor(uri, "r")?.use { it.length } ?: -1L
        } catch (_: Exception) { -1L }
        if (fileSize > MAX_SHARE_FILE_SIZE) {
            _uiState.value = _uiState.value.copy(
                error = "File too large for share (max 100MB)",
            )
            return
        }

        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isSending = true, error = null)
            try {
                for (recipientId in state.selectedUserIds) {
                    fileRepository.uploadFile(
                        recipientId = recipientId,
                        uri = uri,
                    )
                }
                _uiState.value = _uiState.value.copy(
                    isSending = false,
                    sendComplete = true,
                )
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(
                    isSending = false,
                    error = e.message ?: "Failed to send",
                )
            }
        }
    }

    companion object {
        private const val MAX_SHARE_FILE_SIZE = 100_000_000L // 100 MB
    }

    private fun getDisplayName(uri: Uri): String? {
        context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (nameIndex >= 0 && cursor.moveToFirst()) {
                return cursor.getString(nameIndex)
            }
        }
        return uri.lastPathSegment
    }
}
