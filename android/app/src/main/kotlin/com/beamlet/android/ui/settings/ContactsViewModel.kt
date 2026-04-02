package com.beamlet.android.ui.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.beamlet.android.data.api.ContactDto
import com.beamlet.android.data.contacts.ContactRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class ContactsUiState(
    val contacts: List<ContactDto> = emptyList(),
    val isLoading: Boolean = true,
    val contactToRemove: ContactDto? = null,
)

@HiltViewModel
class ContactsViewModel @Inject constructor(
    private val contactRepository: ContactRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow(ContactsUiState())
    val uiState: StateFlow<ContactsUiState> = _uiState.asStateFlow()

    init {
        loadContacts()
    }

    fun loadContacts() {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true)
            try {
                val contacts = contactRepository.listContacts()
                _uiState.value = _uiState.value.copy(
                    contacts = contacts,
                    isLoading = false,
                )
            } catch (_: Exception) {
                _uiState.value = _uiState.value.copy(isLoading = false)
            }
        }
    }

    fun confirmRemove(contact: ContactDto) {
        _uiState.value = _uiState.value.copy(contactToRemove = contact)
    }

    fun dismissRemoveDialog() {
        _uiState.value = _uiState.value.copy(contactToRemove = null)
    }

    fun removeContact(contactId: String) {
        viewModelScope.launch {
            try {
                contactRepository.deleteContact(contactId)
                _uiState.value = _uiState.value.copy(
                    contacts = _uiState.value.contacts.filter { it.id != contactId },
                    contactToRemove = null,
                )
            } catch (_: Exception) {
                _uiState.value = _uiState.value.copy(contactToRemove = null)
            }
        }
    }
}
