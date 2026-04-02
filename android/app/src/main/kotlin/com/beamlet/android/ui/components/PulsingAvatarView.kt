package com.beamlet.android.ui.components

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

@Composable
fun PulsingAvatarView(
    name: String,
    isContact: Boolean,
    isSelected: Boolean,
    size: Dp = 44.dp,
    modifier: Modifier = Modifier,
) {
    val color = when {
        isSelected -> Color(0xFF3478F6)
        isContact -> Color(0xFF3478F6)
        else -> Color(0xFF5AC8FA) // teal
    }

    val infiniteTransition = rememberInfiniteTransition(label = "pulse")

    val pulse1 by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 50f,
        animationSpec = infiniteRepeatable(
            animation = tween(2000, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "pulse1",
    )
    val pulse2 by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 60f,
        animationSpec = infiniteRepeatable(
            animation = tween(2000, delayMillis = 600, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "pulse2",
    )
    val pulse3 by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 70f,
        animationSpec = infiniteRepeatable(
            animation = tween(2000, delayMillis = 1200, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "pulse3",
    )
    val glowAlpha by infiniteTransition.animateFloat(
        initialValue = 0.4f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(1000, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "glow",
    )

    val totalSize = size + 72.dp

    Box(
        modifier = modifier.size(totalSize),
        contentAlignment = Alignment.Center,
    ) {
        // Pulse ring 1
        Box(
            modifier = Modifier
                .size(size + pulse1.dp)
                .alpha((1f - pulse1 / 50f).coerceAtLeast(0f))
                .border(3.dp, color.copy(alpha = 0.5f), CircleShape)
        )
        // Pulse ring 2
        Box(
            modifier = Modifier
                .size(size + pulse2.dp)
                .alpha((1f - pulse2 / 60f).coerceAtLeast(0f))
                .border(2.5.dp, color.copy(alpha = 0.35f), CircleShape)
        )
        // Pulse ring 3
        Box(
            modifier = Modifier
                .size(size + pulse3.dp)
                .alpha((1f - pulse3 / 70f).coerceAtLeast(0f))
                .border(2.dp, color.copy(alpha = 0.2f), CircleShape)
        )

        // Glow halo
        Box(
            modifier = Modifier
                .size(size + 16.dp)
                .alpha(glowAlpha * 0.25f)
                .clip(CircleShape)
                .background(color)
        )

        // Main avatar or checkmark
        if (isSelected) {
            Box(
                modifier = Modifier
                    .size(size)
                    .clip(CircleShape)
                    .background(color.copy(alpha = 0.25f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = Icons.Default.Check,
                    contentDescription = "Selected",
                    tint = color,
                    modifier = Modifier.size(size * 0.35f),
                )
            }
        } else {
            Box(
                modifier = Modifier
                    .shadow(6.dp, CircleShape, ambientColor = color.copy(alpha = 0.4f))
                    .border(2.5.dp, color, CircleShape)
            ) {
                AvatarView(name = name, size = size)
            }
        }
    }
}
