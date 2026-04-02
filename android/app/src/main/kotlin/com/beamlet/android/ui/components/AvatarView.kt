package com.beamlet.android.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.beamlet.android.ui.theme.AvatarColors
import kotlin.math.abs

@Composable
fun AvatarView(
    name: String,
    size: Dp = 40.dp,
    modifier: Modifier = Modifier,
) {
    val initials = computeInitials(name)
    val color = avatarColor(name)

    Box(
        modifier = modifier
            .size(size)
            .clip(CircleShape)
            .background(
                Brush.linearGradient(
                    colors = listOf(color, color.copy(alpha = 0.7f)),
                )
            ),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = initials,
            color = Color.White,
            fontSize = (size.value * 0.4f).sp,
            fontWeight = FontWeight.SemiBold,
        )
    }
}

fun computeInitials(name: String): String {
    val parts = name.trim().split("\\s+".toRegex())
    return if (parts.size >= 2) {
        "${parts[0].first()}${parts[1].first()}".uppercase()
    } else {
        name.take(2).uppercase()
    }
}

fun avatarColor(name: String): Color {
    val hash = name.fold(0) { acc, c -> acc + c.code }
    return AvatarColors[abs(hash) % AvatarColors.size]
}
