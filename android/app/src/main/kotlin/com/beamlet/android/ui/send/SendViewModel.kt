package com.beamlet.android.ui.send

import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.beamlet.android.data.api.ContactDto
import com.beamlet.android.data.contacts.ContactRepository
import com.beamlet.android.data.files.FileRepository
import com.beamlet.android.data.nearby.NearbyService
import com.beamlet.android.data.nearby.NearbyUser
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class SendUiState(
    val contacts: List<ContactDto> = emptyList(),
    val nearbyUsers: List<NearbyUser> = emptyList(),
    val selectedUserIds: Set<String> = emptySet(),
    val attachmentUri: Uri? = null,
    val attachmentDisplayName: String? = null,
    val isPhoto: Boolean = false,
    val isLoadingContacts: Boolean = true,
    val isSending: Boolean = false,
    val error: String? = null,
    val showSuccess: Boolean = false,
)

@HiltViewModel
class SendViewModel @Inject constructor(
    private val contactRepository: ContactRepository,
    private val nearbyService: NearbyService,
    private val fileRepository: FileRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow(SendUiState())
    val uiState: StateFlow<SendUiState> = _uiState.asStateFlow()

    val canSend: Boolean
        get() {
            val s = _uiState.value
            return s.selectedUserIds.isNotEmpty() && s.attachmentUri != null && !s.isSending
        }

    init {
        loadContacts()
        // Collect nearby users
        viewModelScope.launch {
            nearbyService.nearbyUsers.collect { users ->
                _uiState.value = _uiState.value.copy(nearbyUsers = users)
            }
        }
    }

    fun loadContacts() {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoadingContacts = true)
            try {
                val contacts = contactRepository.listContacts()
                _uiState.value = _uiState.value.copy(
                    contacts = contacts,
                    isLoadingContacts = false,
                )
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(isLoadingContacts = false)
            }
        }
    }

    fun setAttachment(uri: Uri, displayName: String, isPhoto: Boolean) {
        _uiState.value = _uiState.value.copy(
            attachmentUri = uri,
            attachmentDisplayName = displayName,
            isPhoto = isPhoto,
            error = null,
        )
    }

    fun clearAttachment() {
        _uiState.value = _uiState.value.copy(
            attachmentUri = null,
            attachmentDisplayName = null,
            isPhoto = false,
        )
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
        val uri = state.attachmentUri ?: return
        if (state.selectedUserIds.isEmpty()) return

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
                    showSuccess = true,
                )
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(
                    isSending = false,
                    error = e.message ?: "Failed to send",
                )
            }
        }
    }

    fun reset() {
        _uiState.value = SendUiState(
            contacts = _uiState.value.contacts,
            isLoadingContacts = false,
        )
    }

}
