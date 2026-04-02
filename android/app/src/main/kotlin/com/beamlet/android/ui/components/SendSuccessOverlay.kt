package com.beamlet.android.ui.components

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Send
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.beamlet.android.ui.theme.BrandBlue
import com.beamlet.android.ui.theme.BrandPurple
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

@Composable
fun SendSuccessOverlay(
    modifier: Modifier = Modifier,
) {
    val dimAlpha = remember { Animatable(0f) }
    val planeAlpha = remember { Animatable(0f) }
    val planeScale = remember { Animatable(0.5f) }
    val planeOffsetX = remember { Animatable(0f) }
    val planeOffsetY = remember { Animatable(0f) }
    val planeRotation = remember { Animatable(0f) }
    val ringScale = remember { Animatable(0.5f) }
    val ringAlpha = remember { Animatable(0f) }
    val textAlpha = remember { Animatable(0f) }

    LaunchedEffect(Unit) {
        // Phase 1: Plane appears with pop
        launch {
            dimAlpha.animateTo(1f, spring(dampingRatio = 0.6f, stiffness = Spring.StiffnessMedium))
        }
        launch {
            planeAlpha.animateTo(1f, spring(dampingRatio = 0.6f, stiffness = Spring.StiffnessMedium))
        }
        launch {
            planeScale.animateTo(1.2f, spring(dampingRatio = 0.6f, stiffness = Spring.StiffnessMedium))
        }

        delay(200)

        // Phase 2: Settle, ring expands
        launch { planeScale.animateTo(1f, tween(200)) }
        launch { ringScale.animateTo(2.5f, tween(600)) }
        launch {
            ringAlpha.animateTo(0.8f, tween(300))
            delay(200)
            ringAlpha.animateTo(0f, tween(400))
        }

        delay(300)

        // Phase 3: Plane flies away
        launch { planeRotation.animateTo(-30f, tween(500)) }
        launch { planeOffsetX.animateTo(150f, tween(500)) }
        launch { planeOffsetY.animateTo(-300f, tween(500)) }
        launch { planeScale.animateTo(0.4f, tween(500)) }
        launch {
            delay(300)
            planeAlpha.animateTo(0f, tween(300))
        }

        // Phase 4: "Sent!" text
        delay(200)
        launch {
            textAlpha.animateTo(1f, spring(dampingRatio = 0.7f, stiffness = Spring.StiffnessMediumLow))
        }
    }

    Box(
        modifier = modifier.fillMaxSize(),
        contentAlignment = Alignment.Center,
    ) {
        // Dim background
        Box(
            modifier = Modifier
                .fillMaxSize()
                .alpha(0.25f * dimAlpha.value)
                .background(Color.Black)
        )

        // Expanding ring
        Canvas(
            modifier = Modifier
                .size(120.dp)
                .scale(ringScale.value)
                .alpha(ringAlpha.value)
        ) {
            drawCircle(
                brush = Brush.verticalGradient(
                    colors = listOf(
                        BrandPurple.copy(alpha = 0.6f),
                        BrandBlue.copy(alpha = 0f),
                    )
                ),
                style = Stroke(width = 3.dp.toPx()),
            )
        }

        // Trail particles
        val trailCount = 8
        for (i in 0 until trailCount) {
            val progress = i.toFloat() / trailCount
            val particleAlpha = (1f - progress * 0.5f) * planeAlpha.value * (1f - textAlpha.value)
            Canvas(
                modifier = Modifier
                    .size((4 + progress * 4).dp)
                    .offset(
                        x = (progress * 80 - 20).dp * (planeOffsetX.value / 150f).coerceIn(0f, 1f),
                        y = (progress * -140 + 20).dp * (planeOffsetY.value / -300f).coerceIn(0f, 1f),
                    )
                    .alpha(particleAlpha)
            ) {
                drawCircle(
                    brush = Brush.linearGradient(
                        colors = listOf(BrandPurple, BrandBlue)
                    )
                )
            }
        }

        // Paper plane icon
        Icon(
            imageVector = Icons.Default.Send,
            contentDescription = null,
            modifier = Modifier
                .size(44.dp)
                .scale(planeScale.value)
                .rotate(planeRotation.value)
                .offset(x = planeOffsetX.value.dp, y = planeOffsetY.value.dp)
                .alpha(planeAlpha.value),
            tint = BrandPurple,
        )

        // "Sent!" text
        Text(
            text = "Sent!",
            fontSize = 18.sp,
            fontWeight = FontWeight.SemiBold,
            color = Color.White,
            modifier = Modifier
                .offset(y = 20.dp)
                .alpha(textAlpha.value),
        )
    }
}
