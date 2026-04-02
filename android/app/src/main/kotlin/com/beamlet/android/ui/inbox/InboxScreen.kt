package com.beamlet.android.ui.inbox

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.Inbox
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.Send
import androidx.compose.material.icons.filled.TextSnippet
import androidx.compose.material.icons.filled.VideoFile
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.beamlet.android.data.api.FileDto
import com.beamlet.android.ui.components.EmptyStateView
import com.beamlet.android.ui.components.ErrorView
import com.beamlet.android.ui.components.LoadingView
import com.beamlet.android.ui.theme.BrandBlue
import java.time.Duration
import java.time.Instant

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InboxScreen(
    onFileClick: (FileDto) -> Unit,
    onImageClick: (String) -> Unit,
    viewModel: InboxViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsState()

    Column(modifier = Modifier.fillMaxSize()) {
        TopAppBar(
            title = { Text("Inbox") },
        )

        // Tabs
        TabRow(
            selectedTabIndex = if (state.selectedTab == InboxTab.RECEIVED) 0 else 1,
        ) {
            Tab(
                selected = state.selectedTab == InboxTab.RECEIVED,
                onClick = { viewModel.selectTab(InboxTab.RECEIVED) },
                text = { Text("Received") },
            )
            Tab(
                selected = state.selectedTab == InboxTab.SENT,
                onClick = { viewModel.selectTab(InboxTab.SENT) },
                text = { Text("Sent") },
            )
        }

        // Content
        Box(modifier = Modifier.fillMaxSize()) {
            when (state.selectedTab) {
                InboxTab.RECEIVED -> ReceivedContent(
                    state = state,
                    authHeaders = viewModel.authHeaders(),
                    thumbnailUrl = { viewModel.thumbnailUrl(it) },
                    onTap = { file ->
                        viewModel.markRead(file.id)
                        if (file.isImage) {
                            onImageClick(file.id)
                        } else {
                            onFileClick(file)
                        }
                    },
                    onPin = { viewModel.togglePin(it) },
                    onDelete = { viewModel.deleteFile(it) },
                    onRetry = { viewModel.loadReceivedFiles() },
                )

                InboxTab.SENT -> SentContent(state = state)
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ReceivedContent(
    state: InboxUiState,
    authHeaders: Map<String, String>,
    thumbnailUrl: (String) -> String?,
    onTap: (FileDto) -> Unit,
    onPin: (String) -> Unit,
    onDelete: (String) -> Unit,
    onRetry: () -> Unit,
) {
    when {
        state.isLoadingReceived && state.receivedFiles.isEmpty() -> {
            LoadingView(message = "Loading inbox...")
        }

        state.error != null && state.receivedFiles.isEmpty() -> {
            ErrorView(message = state.error!!, onRetry = onRetry)
        }

        state.receivedFiles.isEmpty() -> {
            EmptyStateView(
                icon = Icons.Default.Inbox,
                title = "No Files",
                message = "Files sent to you will appear here",
            )
        }

        else -> {
            LazyColumn(
                contentPadding = PaddingValues(vertical = 8.dp),
            ) {
                items(
                    items = state.receivedFiles,
                    key = { it.id },
                ) { file ->
                    val dismissState = rememberSwipeToDismissBoxState(
                        confirmValueChange = { value ->
                            if (value == SwipeToDismissBoxValue.EndToStart) {
                                onDelete(file.id)
                                true
                            } else {
                                false
                            }
                        },
                    )

                    SwipeToDismissBox(
                        state = dismissState,
                        backgroundContent = {
                            Box(
                                modifier = Modifier
                                    .fillMaxSize()
                                    .background(MaterialTheme.colorScheme.error)
                                    .padding(horizontal = 20.dp),
                                contentAlignment = Alignment.CenterEnd,
                            ) {
                                Icon(
                                    imageVector = Icons.Default.Delete,
                                    contentDescription = "Delete",
                                    tint = Color.White,
                                )
                            }
                        },
                        enableDismissFromStartToEnd = false,
                    ) {
                        InboxItemCard(
                            file = file,
                            thumbnailUrl = thumbnailUrl(file.id),
                            authHeaders = authHeaders,
                            onTap = { onTap(file) },
                            onPin = { onPin(file.id) },
                            onDelete = { onDelete(file.id) },
                        )
                    }
                    HorizontalDivider(
                        thickness = 0.5.dp,
                        color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.3f),
                    )
                }
            }
        }
    }
}

@Composable
private fun SentContent(state: InboxUiState) {
    val context = LocalContext.current

    when {
        state.isLoadingSent && state.sentFiles.isEmpty() -> {
            LoadingView(message = "Loading sent files...")
        }

        state.sentFiles.isEmpty() -> {
            EmptyStateView(
                icon = Icons.Default.Send,
                title = "No Sent Files",
                message = "Files you send will appear here",
            )
        }

        else -> {
            LazyColumn(
                contentPadding = PaddingValues(vertical = 4.dp),
            ) {
                items(
                    items = state.sentFiles,
                    key = { it.id },
                ) { file ->
                    SentFileRow(file = file)
                    HorizontalDivider(
                        thickness = 0.5.dp,
                        color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.3f),
                    )
                }
            }
        }
    }
}

@Composable
private fun SentFileRow(file: FileDto) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
    ) {
        // Type icon
        Box(
            modifier = Modifier
                .size(50.dp)
                .clip(RoundedCornerShape(10.dp))
                .background(BrandBlue.copy(alpha = 0.12f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = when {
                    file.isImage -> Icons.Default.Image
                    file.isVideo -> Icons.Default.VideoFile
                    file.isText -> Icons.Default.TextSnippet
                    else -> Icons.Default.Description
                },
                contentDescription = null,
                tint = BrandBlue,
                modifier = Modifier.size(24.dp),
            )
        }

        Spacer(modifier = Modifier.width(14.dp))

        Column(modifier = Modifier.weight(1f)) {
            Row(
                horizontalArrangement = Arrangement.SpaceBetween,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(
                    text = "To: ${file.recipientName ?: file.senderName ?: "Unknown"}",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                )

                Row(verticalAlignment = Alignment.CenterVertically) {
                    if (file.read) {
                        Icon(
                            imageVector = Icons.Default.CheckCircle,
                            contentDescription = null,
                            modifier = Modifier.size(12.dp),
                            tint = Color(0xFF34C759),
                        )
                        Spacer(modifier = Modifier.width(3.dp))
                        Text(
                            text = "Read",
                            style = MaterialTheme.typography.labelSmall,
                            color = Color(0xFF34C759),
                        )
                    } else {
                        Icon(
                            imageVector = Icons.Default.RadioButtonUnchecked,
                            contentDescription = null,
                            modifier = Modifier.size(12.dp),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Spacer(modifier = Modifier.width(3.dp))
                        Text(
                            text = "Delivered",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(2.dp))

            file.createdAt?.let { instant ->
                Text(
                    text = formatRelativeTimeSent(instant),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
                )
            }
        }
    }
}

private fun formatRelativeTimeSent(instant: Instant): String {
    val now = Instant.now()
    val duration = Duration.between(instant, now)
    val seconds = duration.seconds
    return when {
        seconds < 60 -> "just now"
        seconds < 3600 -> "${seconds / 60}m ago"
        seconds < 86400 -> "${seconds / 3600}h ago"
        seconds < 604800 -> "${seconds / 86400}d ago"
        else -> "${seconds / 604800}w ago"
    }
}
