package com.beamlet.android.shareactivity

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.animation.core.EaseOut
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.beamlet.android.data.nearby.NearbyUser
import com.beamlet.android.ui.components.AvatarView
import com.beamlet.android.ui.theme.BeamletTheme
import com.beamlet.android.ui.theme.BrandBlue
import dagger.hilt.android.AndroidEntryPoint

@AndroidEntryPoint
class ShareActivity : ComponentActivity() {

    private val viewModel: ShareViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        viewModel.processIntent(intent)

        setContent {
            BeamletTheme {
                ShareSheet(
                    viewModel = viewModel,
                    onClose = { finish() },
                )
            }
        }
    }
}

@Composable
private fun ShareSheet(
    viewModel: ShareViewModel,
    onClose: () -> Unit,
) {
    val state by viewModel.uiState.collectAsState()

    LaunchedEffect(state.sendComplete) {
        if (state.sendComplete) {
            kotlinx.coroutines.delay(800)
            onClose()
        }
    }

    // Bottom-sheet style: dark scrim background, content at bottom
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.4f))
            .clickable(indication = null, interactionSource = androidx.compose.foundation.interaction.MutableInteractionSource()) { onClose() },
        contentAlignment = Alignment.BottomCenter,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(topStart = 24.dp, topEnd = 24.dp))
                .background(MaterialTheme.colorScheme.surface)
                .clickable(indication = null, interactionSource = androidx.compose.foundation.interaction.MutableInteractionSource()) { /* consume clicks */ }
                .padding(top = 12.dp, bottom = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            // Handle bar
            Box(
                modifier = Modifier
                    .size(width = 40.dp, height = 4.dp)
                    .clip(RoundedCornerShape(2.dp))
                    .background(MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.3f)),
            )

            Spacer(modifier = Modifier.height(16.dp))

            // File info
            if (state.displayName != null) {
                Text(
                    text = state.displayName!!,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.Medium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.padding(horizontal = 24.dp),
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = "Tap a contact to send",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(modifier = Modifier.height(20.dp))
            }

            // Status messages
            when {
                state.isSending -> {
                    CircularProgressIndicator(
                        modifier = Modifier.size(32.dp).padding(8.dp),
                        strokeWidth = 2.dp,
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    Text("Sending...", style = MaterialTheme.typography.bodySmall)
                    Spacer(modifier = Modifier.height(16.dp))
                }
                state.sendComplete -> {
                    Text(
                        text = "✓ Sent!",
                        fontSize = 20.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = Color(0xFF34C759),
                    )
                    Spacer(modifier = Modifier.height(16.dp))
                }
                state.error != null -> {
                    Text(
                        text = state.error!!,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error,
                        modifier = Modifier.padding(horizontal = 24.dp),
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                }
            }

            // Combined grid: nearby + contacts
            if (!state.isSending && !state.sendComplete) {
                val allUsers = buildList {
                    state.nearbyUsers.forEach { add(ShareTarget.Nearby(it)) }
                    state.contacts.forEach { add(ShareTarget.Contact(it.id, it.name)) }
                }

                if (state.isLoadingContacts) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(24.dp).padding(vertical = 16.dp),
                    )
                } else {
                    LazyVerticalGrid(
                        columns = GridCells.Fixed(4),
                        horizontalArrangement = Arrangement.spacedBy(4.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp)
                            .height(280.dp),
                    ) {
                        items(allUsers, key = { it.id }) { target ->
                            ShareTargetItem(
                                target = target,
                                isSelected = state.selectedUserIds.contains(target.id),
                                onTap = {
                                    viewModel.toggleUser(target.id)
                                    // Auto-send on single tap if only one selected
                                    if (!state.selectedUserIds.contains(target.id)) {
                                        viewModel.send()
                                    }
                                },
                            )
                        }
                    }
                }
            }
        }
    }
}

private sealed class ShareTarget {
    abstract val id: String
    abstract val name: String

    data class Nearby(val user: NearbyUser) : ShareTarget() {
        override val id = user.id
        override val name = user.name
    }

    data class Contact(override val id: String, override val name: String) : ShareTarget()
}

@Composable
private fun ShareTargetItem(
    target: ShareTarget,
    isSelected: Boolean,
    onTap: () -> Unit,
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier
            .clip(RoundedCornerShape(12.dp))
            .clickable { onTap() }
            .padding(vertical = 6.dp, horizontal = 4.dp),
    ) {
        Box(contentAlignment = Alignment.Center) {
            // Pulse ring for nearby users
            if (target is ShareTarget.Nearby) {
                val transition = rememberInfiniteTransition(label = "pulse")
                val pulseScale by transition.animateFloat(
                    initialValue = 1f,
                    targetValue = 1.4f,
                    animationSpec = infiniteRepeatable(
                        animation = tween(1200, easing = EaseOut),
                        repeatMode = RepeatMode.Restart,
                    ),
                    label = "scale",
                )
                val pulseAlpha by transition.animateFloat(
                    initialValue = 0.5f,
                    targetValue = 0f,
                    animationSpec = infiniteRepeatable(
                        animation = tween(1200, easing = EaseOut),
                        repeatMode = RepeatMode.Restart,
                    ),
                    label = "alpha",
                )
                Box(
                    modifier = Modifier
                        .size(56.dp)
                        .scale(pulseScale)
                        .alpha(pulseAlpha)
                        .border(2.dp, Color(0xFF14B8A6), CircleShape),
                )
            }

            AvatarView(name = target.name, size = 52.dp)

            // Selection indicator
            if (isSelected) {
                Icon(
                    imageVector = Icons.Default.CheckCircle,
                    contentDescription = null,
                    tint = BrandBlue,
                    modifier = Modifier
                        .align(Alignment.BottomEnd)
                        .size(18.dp),
                )
            } else if (target is ShareTarget.Nearby) {
                Box(
                    modifier = Modifier
                        .align(Alignment.BottomEnd)
                        .size(10.dp)
                        .clip(CircleShape)
                        .background(Color(0xFF34C759)),
                )
            }
        }

        Spacer(modifier = Modifier.height(4.dp))

        Text(
            text = target.name,
            style = MaterialTheme.typography.labelSmall,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            textAlign = TextAlign.Center,
            modifier = Modifier.width(72.dp),
        )
    }
}
