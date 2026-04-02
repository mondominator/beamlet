package com.beamlet.android.ui.settings

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.PersonRemove
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.beamlet.android.data.api.ContactDto
import com.beamlet.android.ui.components.AvatarView
import com.beamlet.android.ui.components.EmptyStateView
import com.beamlet.android.ui.components.LoadingView
import com.beamlet.android.util.formatRelativeTime

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ContactsScreen(
    onBack: () -> Unit,
    viewModel: ContactsViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsState()

    Column(modifier = Modifier.fillMaxSize()) {
        TopAppBar(
            title = { Text("Contacts") },
            navigationIcon = {
                IconButton(onClick = onBack) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                }
            },
        )

        when {
            state.isLoading -> {
                LoadingView(message = "Loading contacts...")
            }

            state.contacts.isEmpty() -> {
                EmptyStateView(
                    icon = Icons.Default.People,
                    title = "No contacts yet",
                    message = "Add contacts from Settings to start sharing",
                )
            }

            else -> {
                LazyColumn(modifier = Modifier.fillMaxSize()) {
                    items(
                        items = state.contacts,
                        key = { it.id },
                    ) { contact ->
                        ContactRow(
                            contact = contact,
                            onRemove = { viewModel.confirmRemove(contact) },
                        )
                        HorizontalDivider(
                            thickness = 0.5.dp,
                            color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.3f),
                        )
                    }
                }
            }
        }
    }

    // Remove confirmation dialog
    state.contactToRemove?.let { contact ->
        AlertDialog(
            onDismissRequest = { viewModel.dismissRemoveDialog() },
            title = { Text("Remove Contact") },
            text = {
                Text("Remove ${contact.name}? You won't be able to send files to this person until you reconnect.")
            },
            confirmButton = {
                TextButton(onClick = { viewModel.removeContact(contact.id) }) {
                    Text("Remove", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { viewModel.dismissRemoveDialog() }) {
                    Text("Cancel")
                }
            },
        )
    }
}

@Composable
private fun ContactRow(
    contact: ContactDto,
    onRemove: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        AvatarView(name = contact.name, size = 44.dp)

        Spacer(modifier = Modifier.width(14.dp))

        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = contact.name,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
            )
            contact.createdAt?.let { instant ->
                Text(
                    text = "Connected ${formatRelativeTime(instant)}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
                )
            }
        }

        IconButton(onClick = onRemove) {
            Icon(
                imageVector = Icons.Default.PersonRemove,
                contentDescription = "Remove contact",
                tint = MaterialTheme.colorScheme.error.copy(alpha = 0.7f),
            )
        }
    }
}

