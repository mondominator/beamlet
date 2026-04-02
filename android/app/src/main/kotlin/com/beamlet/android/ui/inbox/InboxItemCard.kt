package com.beamlet.android.ui.inbox

import android.text.format.Formatter
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.OpenInBrowser
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.VideoFile
import androidx.compose.material.icons.filled.ZoomOutMap
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.beamlet.android.data.api.FileDto
import com.beamlet.android.ui.components.AuthenticatedImage
import com.beamlet.android.ui.components.AvatarView
import com.beamlet.android.ui.theme.BrandBlue
import com.beamlet.android.ui.theme.BrandPurple
import java.time.Duration
import java.time.Instant

@Composable
fun InboxItemCard(
    file: FileDto,
    thumbnailUrl: String?,
    authHeaders: Map<String, String>,
    onTap: () -> Unit,
    onPin: () -> Unit,
    onDelete: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var showContextMenu by remember { mutableStateOf(false) }

    Column(
        modifier = modifier
            .fillMaxWidth()
            .clickable { onTap() }
            .background(MaterialTheme.colorScheme.surface)
            .padding(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 12.dp),
    ) {
        // Sender header
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth(),
        ) {
            AvatarView(name = file.senderName ?: "?", size = 28.dp)

            Spacer(modifier = Modifier.width(8.dp))

            Text(
                text = file.senderName ?: "Unknown",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
            )

            if (!file.read) {
                Spacer(modifier = Modifier.width(6.dp))
                Box(
                    modifier = Modifier
                        .size(7.dp)
                        .clip(CircleShape)
                        .background(
                            Brush.linearGradient(listOf(BrandPurple, BrandBlue))
                        )
                )
            }

            if (file.pinned) {
                Spacer(modifier = Modifier.width(4.dp))
                Icon(
                    imageVector = Icons.Default.PushPin,
                    contentDescription = "Pinned",
                    modifier = Modifier.size(12.dp),
                    tint = Color(0xFFFF9500),
                )
            }

            Spacer(modifier = Modifier.weight(1f))

            file.createdAt?.let { instant ->
                Text(
                    text = formatRelativeTime(instant),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
                )
            }
        }

        Spacer(modifier = Modifier.height(8.dp))

        // Content area — varies by type
        Box(modifier = Modifier.fillMaxWidth()) {
            when {
                file.isImage -> ImageContent(thumbnailUrl, authHeaders)
                file.isVideo -> VideoContent(file, thumbnailUrl, authHeaders)
                file.isText -> TextContent(file.textContent ?: "")
                file.isLink -> LinkContent(file.textContent ?: "")
                else -> GenericFileContent(file)
            }

            // Long-press context menu
            DropdownMenu(
                expanded = showContextMenu,
                onDismissRequest = { showContextMenu = false },
            ) {
                if (file.isImage) {
                    DropdownMenuItem(
                        text = { Text("View Full Size") },
                        leadingIcon = { Icon(Icons.Default.ZoomOutMap, null) },
                        onClick = {
                            showContextMenu = false
                            onTap()
                        },
                    )
                }
                if (file.isText && file.textContent != null) {
                    DropdownMenuItem(
                        text = { Text("Copy Text") },
                        leadingIcon = { Icon(Icons.Default.ContentCopy, null) },
                        onClick = { showContextMenu = false },
                    )
                }
                DropdownMenuItem(
                    text = { Text(if (file.pinned) "Unpin" else "Pin") },
                    leadingIcon = { Icon(Icons.Default.PushPin, null) },
                    onClick = {
                        showContextMenu = false
                        onPin()
                    },
                )
                DropdownMenuItem(
                    text = { Text("Delete") },
                    leadingIcon = {
                        Icon(
                            Icons.Default.Delete,
                            null,
                            tint = MaterialTheme.colorScheme.error,
                        )
                    },
                    onClick = {
                        showContextMenu = false
                        onDelete()
                    },
                )
            }
        }
    }
}

@Composable
private fun ImageContent(
    thumbnailUrl: String?,
    authHeaders: Map<String, String>,
) {
    if (thumbnailUrl != null) {
        AuthenticatedImage(
            url = thumbnailUrl,
            authHeaders = authHeaders,
            contentScale = ContentScale.Fit,
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(max = 200.dp)
                .clip(RoundedCornerShape(14.dp)),
        )
    }
}

@Composable
private fun VideoContent(
    file: FileDto,
    thumbnailUrl: String?,
    authHeaders: Map<String, String>,
) {
    if (thumbnailUrl != null) {
        Box(contentAlignment = Alignment.Center) {
            AuthenticatedImage(
                url = thumbnailUrl,
                authHeaders = authHeaders,
                contentScale = ContentScale.Fit,
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(max = 200.dp)
                    .clip(RoundedCornerShape(14.dp)),
            )
            Icon(
                imageVector = Icons.Default.PlayCircle,
                contentDescription = "Play video",
                modifier = Modifier.size(48.dp),
                tint = Color.White.copy(alpha = 0.9f),
            )
        }
    } else {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(14.dp))
                .background(BrandPurple.copy(alpha = 0.08f))
                .padding(14.dp),
        ) {
            Icon(
                imageVector = Icons.Default.VideoFile,
                contentDescription = null,
                tint = BrandPurple,
            )
            Spacer(modifier = Modifier.width(10.dp))
            Text(
                text = file.filename,
                style = MaterialTheme.typography.bodyMedium,
            )
        }
    }
}

@Composable
private fun TextContent(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.bodyLarge,
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .padding(14.dp),
    )
}

@Composable
private fun LinkContent(text: String) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(BrandBlue.copy(alpha = 0.08f))
            .padding(14.dp),
    ) {
        Icon(
            imageVector = Icons.Default.OpenInBrowser,
            contentDescription = null,
            tint = BrandBlue,
            modifier = Modifier.size(24.dp),
        )
        Spacer(modifier = Modifier.width(10.dp))
        Text(
            text = text,
            style = MaterialTheme.typography.bodySmall,
            color = BrandBlue,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f),
        )
        Spacer(modifier = Modifier.width(8.dp))
        Icon(
            imageVector = Icons.AutoMirrored.Filled.OpenInNew,
            contentDescription = null,
            modifier = Modifier.size(14.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f),
        )
    }
}

@Composable
private fun GenericFileContent(file: FileDto) {
    val context = LocalContext.current
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .padding(14.dp),
    ) {
        Icon(
            imageVector = Icons.Default.Description,
            contentDescription = null,
            modifier = Modifier.size(28.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(modifier = Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = file.filename,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.Medium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = file.formattedSize(context),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Spacer(modifier = Modifier.width(8.dp))
        Icon(
            imageVector = Icons.Default.Download,
            contentDescription = "Download",
            tint = BrandBlue,
            modifier = Modifier.size(24.dp),
        )
    }
}

private fun formatRelativeTime(instant: Instant): String {
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
