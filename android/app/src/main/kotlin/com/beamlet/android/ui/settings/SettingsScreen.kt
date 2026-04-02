package com.beamlet.android.ui.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Circle
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    onNavigateToContacts: () -> Unit,
    onNavigateToAddContact: () -> Unit,
    onNavigateToScanner: () -> Unit,
    viewModel: SettingsViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsState()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState()),
    ) {
        TopAppBar(title = { Text("Settings") })

        // Contacts section
        SectionHeader("Contacts")
        SettingsRow(
            icon = Icons.Default.People,
            title = "My Contacts",
            onClick = onNavigateToContacts,
        )
        SettingsRow(
            icon = Icons.Default.PersonAdd,
            title = "Add Contact",
            onClick = onNavigateToAddContact,
        )
        SettingsRow(
            icon = Icons.Default.QrCodeScanner,
            title = "Scan Invite",
            onClick = onNavigateToScanner,
        )

        // Server section
        SectionHeader("Server")
        state.serverUrl?.let { url ->
            SettingsLabelValue("URL", url)
        }
        SettingsLabelValue("Status") {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = Icons.Default.Circle,
                    contentDescription = null,
                    modifier = Modifier.size(8.dp),
                    tint = Color(0xFF34C759),
                )
                Spacer(modifier = Modifier.width(6.dp))
                Text(
                    text = "Connected",
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
        }

        // Notifications section
        SectionHeader("Notifications")
        SettingsLabelValue("Push") {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (state.fcmToken != null) {
                    Icon(
                        imageVector = Icons.Default.Circle,
                        contentDescription = null,
                        modifier = Modifier.size(8.dp),
                        tint = Color(0xFF34C759),
                    )
                    Spacer(modifier = Modifier.width(6.dp))
                    Text(
                        text = "Enabled",
                        style = MaterialTheme.typography.bodyMedium,
                    )
                } else {
                    Text(
                        text = "Not registered",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }

        // Usage section
        SectionHeader("Usage")
        SettingsLabelValue(
            "Files Sent",
            state.filesSent?.toString() ?: "\u2014",
        )
        SettingsLabelValue(
            "Files Received",
            state.filesReceived?.toString() ?: "\u2014",
        )
        SettingsLabelValue(
            "Storage Used",
            state.storageUsed?.let { viewModel.formatBytes(it) } ?: "\u2014",
        )

        // Storage section
        SectionHeader("Storage")
        SettingsLabelValue(
            "File Cleanup",
            "${state.fileExpiryDays} day${if (state.fileExpiryDays != 1) "s" else ""}",
        )
        Text(
            text = "Files you send will be automatically deleted from the server after this period.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
        )

        // Appearance section
        SectionHeader("Appearance")
        SettingsLabelValue("Theme", state.appTheme.replaceFirstChar { it.uppercase() })

        // About section
        SectionHeader("About")
        SettingsLabelValue("Version", "1.0")

        Spacer(modifier = Modifier.height(16.dp))

        // Disconnect button
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable { viewModel.showDisconnectDialog() }
                .padding(horizontal = 16.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                imageVector = Icons.AutoMirrored.Filled.Logout,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.error,
                modifier = Modifier.size(20.dp),
            )
            Spacer(modifier = Modifier.width(12.dp))
            Text(
                text = "Disconnect",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.error,
            )
        }

        Spacer(modifier = Modifier.height(40.dp))
    }

    // Disconnect confirmation dialog
    if (state.showDisconnectDialog) {
        AlertDialog(
            onDismissRequest = { viewModel.dismissDisconnectDialog() },
            title = { Text("Disconnect?") },
            text = { Text("You'll need to re-enter your server details to reconnect.") },
            confirmButton = {
                TextButton(onClick = { viewModel.disconnect() }) {
                    Text("Disconnect", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { viewModel.dismissDisconnectDialog() }) {
                    Text("Cancel")
                }
            },
        )
    }
}

@Composable
private fun SectionHeader(title: String) {
    Text(
        text = title,
        style = MaterialTheme.typography.titleSmall,
        fontWeight = FontWeight.SemiBold,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 24.dp, bottom = 8.dp),
    )
}

@Composable
private fun SettingsRow(
    icon: ImageVector,
    title: String,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            modifier = Modifier.size(20.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(modifier = Modifier.width(12.dp))
        Text(
            text = title,
            style = MaterialTheme.typography.bodyLarge,
            modifier = Modifier.weight(1f),
        )
        Icon(
            imageVector = Icons.Default.ChevronRight,
            contentDescription = null,
            modifier = Modifier.size(20.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f),
        )
    }
}

@Composable
private fun SettingsLabelValue(
    label: String,
    value: String,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.weight(1f),
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun SettingsLabelValue(
    label: String,
    content: @Composable () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.weight(1f),
        )
        content()
    }
}
