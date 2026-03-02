package com.precor.treadmill.ui.components

import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.automirrored.filled.DirectionsRun
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Settings
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.max
import androidx.compose.ui.unit.sp

@Composable
fun TabBar(
    currentRoute: String,
    voiceState: String, // "idle", "listening", "speaking"
    onNavigate: (String) -> Unit,
    onVoiceToggle: () -> Unit,
    onSettingsToggle: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val isRunRoute = currentRoute.startsWith("running")

    // Hide tab bar during running screen (BottomBar takes over)
    if (isRunRoute) return

    val bottomSafe = WindowInsets.safeDrawing.asPaddingValues().calculateBottomPadding()
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(bottom = bottomSafe)
            .height(60.dp)
            .background(Color(0xFF121210))
            .padding(horizontal = 24.dp),
        horizontalArrangement = Arrangement.SpaceAround,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        TabItem(
            icon = Icons.Default.Home,
            label = "Home",
            selected = currentRoute == "lobby",
            onClick = { onNavigate("lobby") },
        )
        TabItem(
            icon = Icons.AutoMirrored.Filled.DirectionsRun,
            label = "Run",
            selected = isRunRoute,
            onClick = { onNavigate("running") },
        )
        // Voice button with state-dependent color and glow
        VoiceTabItem(
            voiceState = voiceState,
            onClick = onVoiceToggle,
        )
        TabItem(
            icon = Icons.Default.Settings,
            label = "Settings",
            selected = false,
            onClick = onSettingsToggle,
        )
    }
}

@Composable
private fun TabItem(
    icon: ImageVector,
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
    tint: Color? = null,
    modifier: Modifier = Modifier,
) {
    val color = tint ?: if (selected) Color(0xFFE8E4DF) else Color(0x59E8E4DF)

    Column(
        modifier = modifier
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                onClick = onClick,
            )
            .padding(vertical = 4.dp, horizontal = 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = label,
            tint = color,
            modifier = Modifier.size(24.dp),
        )
        Spacer(Modifier.height(2.dp))
        Text(
            text = label,
            color = color,
            fontSize = 10.sp,
        )
    }
}

@Composable
private fun VoiceTabItem(
    voiceState: String,
    onClick: () -> Unit,
) {
    val active = voiceState == "listening" || voiceState == "speaking"
    val isListening = voiceState == "listening"
    val glowColor = when (voiceState) {
        "listening" -> Color(0xFFC45C52)
        "speaking" -> Color(0xFF8B7FA0)
        else -> Color.Transparent
    }

    val infiniteTransition = rememberInfiniteTransition(label = "tabMicGlow")
    val pulseAlpha by infiniteTransition.animateFloat(
        initialValue = 0.6f,
        targetValue = if (isListening) 0.15f else 0.4f,
        animationSpec = infiniteRepeatable(
            animation = tween(if (isListening) 1000 else 1600, easing = EaseInOut),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "tabPulseAlpha",
    )

    val color = when (voiceState) {
        "listening" -> Color(0xFFC45C52)
        "speaking" -> Color(0xFF8B7FA0)
        else -> Color(0x59E8E4DF)
    }

    Column(
        modifier = Modifier
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                onClick = onClick,
            )
            .padding(vertical = 4.dp, horizontal = 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(
            imageVector = Icons.Default.Mic,
            contentDescription = when (voiceState) {
                "listening" -> "Listening"
                "speaking" -> "Speaking"
                else -> "Voice"
            },
            tint = color,
            modifier = Modifier
                .size(24.dp)
                .drawBehind {
                    if (active) {
                        drawCircle(
                            color = glowColor.copy(alpha = pulseAlpha),
                            radius = size.minDimension * 0.9f,
                        )
                    }
                },
        )
        Spacer(Modifier.height(2.dp))
        Text(
            text = when (voiceState) {
                "listening" -> "Listening"
                "speaking" -> "Speaking"
                else -> "Voice"
            },
            color = color,
            fontSize = 10.sp,
        )
    }
}
