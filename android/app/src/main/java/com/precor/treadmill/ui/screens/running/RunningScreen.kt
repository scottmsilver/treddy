package com.precor.treadmill.ui.screens.running

import android.content.res.Configuration
import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.max
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import com.precor.treadmill.ui.components.HistoryList
import com.precor.treadmill.ui.theme.TimerFontFamily
import com.precor.treadmill.ui.util.glowText
import com.precor.treadmill.ui.util.timerText
import com.precor.treadmill.ui.util.haptic
import com.precor.treadmill.ui.viewmodel.TreadmillViewModel
import kotlinx.coroutines.delay

@Composable
fun RunningScreen(
    viewModel: TreadmillViewModel,
    onVoiceToggle: (String?) -> Unit,
    modifier: Modifier = Modifier,
) {
    val sess by viewModel.derivedSession.collectAsState()
    val pgm by viewModel.derivedProgram.collectAsState()
    val status by viewModel.status.collectAsState()
    val encouragement by viewModel.encouragement.collectAsState()
    val context = LocalContext.current

    // Auto-clear encouragement after 4 seconds
    LaunchedEffect(encouragement) {
        if (encouragement != null) {
            delay(4000)
            viewModel.clearEncouragement()
        }
    }

    val isManual = pgm.program?.manual == true
    val physicalActive = sess.active || pgm.running

    // Delayed visual active state for manual programs
    // Initialize to current state so rotation doesn't re-trigger enter animation
    var visualActive by remember { mutableStateOf(physicalActive) }
    LaunchedEffect(physicalActive, isManual, status.emuSpeed, status.emuIncline) {
        if (physicalActive && isManual && !visualActive) {
            delay(1200)
            visualActive = true
        } else if (physicalActive && !isManual) {
            visualActive = true
        } else if (!physicalActive) {
            visualActive = false
        }
    }

    val isActive = visualActive
    // Pre-seed transition so rotation doesn't re-trigger enter animation
    val timerVisible = remember { MutableTransitionState(isActive) }
    timerVisible.targetState = isActive
    var durationEditOpen by remember { mutableStateOf(false) }
    val configuration = LocalConfiguration.current
    val isLandscape = configuration.orientation == Configuration.ORIENTATION_LANDSCAPE

    if (isLandscape) {
        // Landscape: side-by-side layout
        RunningScreenLandscape(
            viewModel = viewModel,
            onVoiceToggle = onVoiceToggle,
            timerVisible = timerVisible,
            isManual = isManual,
            durationEditOpen = durationEditOpen,
            onDurationEditToggle = { durationEditOpen = !durationEditOpen },
            modifier = modifier,
        )
        return
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .background(Color(0xFF121210))
            .statusBarsPadding(),
    ) {
        // Header with hero timer
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 4.dp, start = 16.dp, end = 16.dp, bottom = 4.dp),
        ) {
            // Ambient glow
            if (isActive) {
                Box(
                    modifier = Modifier
                        .size(200.dp, 140.dp)
                        .align(Alignment.Center)
                        .blur(50.dp)
                        .background(
                            brush = Brush.radialGradient(
                                colors = listOf(Color(0xFF6B8F8B).copy(alpha = 0.25f), Color.Transparent),
                            ),
                        ),
                )
            }

            // Hero timer
            Column(
                modifier = Modifier.fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                AnimatedVisibility(
                    visibleState = timerVisible,
                    enter = fadeIn() + scaleIn(initialScale = 0.8f),
                    exit = fadeOut() + scaleOut(targetScale = 0.8f),
                ) {
                    // Bounce only on timer↔encouragement transition, not on text changes within
                    AnimatedContent(
                        targetState = encouragement != null,
                        transitionSpec = {
                            (scaleIn(
                                animationSpec = spring(dampingRatio = 0.6f),
                                initialScale = 0.85f,
                            ) + fadeIn()) togetherWith (scaleOut(
                                targetScale = 0.85f,
                            ) + fadeOut()) using SizeTransform(clip = false)
                        },
                        contentAlignment = Alignment.Center,
                        label = "hero-bounce",
                    ) { showEncouragement ->
                        if (showEncouragement) {
                            Text(
                                text = glowText(encouragement ?: ""),
                                color = Color(0xFF6BC89B),
                                fontSize = 28.sp,
                                fontWeight = FontWeight.Medium,
                                fontFamily = TimerFontFamily,
                                letterSpacing = (-0.03).em,
                                textAlign = TextAlign.Center,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(vertical = 16.dp),
                            )
                        } else {
                            Text(
                                text = timerText(sess.elapsedDisplay),
                                textAlign = TextAlign.Center,
                                style = TextStyle(
                                    color = Color(0xFFE8E4DF),
                                    fontSize = 96.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    fontFamily = TimerFontFamily,
                                    lineHeight = 96.sp,
                                    letterSpacing = (-0.03).em,
                                    fontFeatureSettings = "tnum",
                                ),
                                modifier = Modifier
                                    .clickable(
                                        enabled = isManual && pgm.running,
                                        interactionSource = remember { MutableInteractionSource() },
                                        indication = null,
                                    ) {
                                        durationEditOpen = !durationEditOpen
                                        haptic(context, 10)
                                    },
                            )
                        }
                    }
                }

                // Duration edit buttons
                AnimatedVisibility(
                    visible = durationEditOpen && isManual && pgm.running,
                    enter = fadeIn() + expandVertically(),
                    exit = fadeOut() + shrinkVertically(),
                ) {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        modifier = Modifier.padding(top = 8.dp),
                    ) {
                        for (d in listOf(-10, -5, 5, 10)) {
                            DurationButton(d) {
                                viewModel.adjustDuration(d * 60)
                                haptic(context, 25)
                            }
                        }
                    }
                }
            }
        }

        // Metrics row
        MetricsRow(viewModel = viewModel)

        // Main content area (HUD / Complete / Idle)
        Box(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .padding(top = 6.dp),
        ) {
            AnimatedContent(
                targetState = when {
                    pgm.program != null && pgm.running -> "hud"
                    pgm.completed -> "complete"
                    else -> "idle"
                },
                transitionSpec = {
                    fadeIn() + scaleIn(initialScale = 0.96f) togetherWith
                            fadeOut() + scaleOut(targetScale = 0.96f)
                },
                label = "run-content",
            ) { state ->
                when (state) {
                    "hud" -> ProgramHUD(viewModel = viewModel, modifier = Modifier.fillMaxSize())
                    "complete" -> {
                        Column(modifier = Modifier.fillMaxSize()) {
                            ProgramComplete(
                                viewModel = viewModel,
                                onVoice = { haptic(context, 20); onVoiceToggle(null) },
                                modifier = Modifier.weight(1f),
                            )
                            HistoryList(
                                variant = "compact",
                            )
                        }
                    }
                    else -> {
                        IdleCard(
                            viewModel = viewModel,
                            onVoice = { prompt -> haptic(context, 20); onVoiceToggle(prompt) },
                            modifier = Modifier.fillMaxSize(),
                        )
                    }
                }
            }
        }

        // Bottom bar
        BottomBar(viewModel = viewModel)
    }
}

@Composable
private fun RunningScreenLandscape(
    viewModel: TreadmillViewModel,
    onVoiceToggle: (String?) -> Unit,
    timerVisible: MutableTransitionState<Boolean>,
    isManual: Boolean,
    durationEditOpen: Boolean,
    onDurationEditToggle: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val sess by viewModel.derivedSession.collectAsState()
    val pgm by viewModel.derivedProgram.collectAsState()
    val encouragement by viewModel.encouragement.collectAsState()
    val context = LocalContext.current

    // Use BoxWithConstraints to scale elements proportionally to available height
    BoxWithConstraints(
        modifier = modifier
            .fillMaxSize()
            .background(Color(0xFF121210))
            .systemBarsPadding(),
    ) {
        // Proportional scaling (reference: ~740dp tablet landscape)
        val h = maxHeight.value
        val w = maxWidth.value
        val timerFontSize = (h * 0.14f).coerceIn(48f, 140f).sp
        val encourageFontSize = (h * 0.05f).coerceIn(18f, 42f).sp
        val timerPadTop = (h * 0.02f).coerceIn(4f, 16f).dp
        val metricsScale = (h / 380f).coerceIn(1f, 2f)
        val controlsWidth = (w * 0.28f).coerceIn(240f, 400f).dp

        Column(modifier = Modifier.fillMaxSize()) {
            // Timer — wraps content, proportional font + padding
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(start = 12.dp, end = 12.dp, top = timerPadTop),
                contentAlignment = Alignment.Center,
            ) {
                Column(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    AnimatedVisibility(
                        visibleState = timerVisible,
                        enter = fadeIn() + scaleIn(initialScale = 0.8f),
                        exit = fadeOut() + scaleOut(targetScale = 0.8f),
                    ) {
                        AnimatedContent(
                            targetState = encouragement != null,
                            transitionSpec = {
                                (scaleIn(
                                    animationSpec = spring(dampingRatio = 0.6f),
                                    initialScale = 0.85f,
                                ) + fadeIn()) togetherWith (scaleOut(
                                    targetScale = 0.85f,
                                ) + fadeOut()) using SizeTransform(clip = false)
                            },
                            contentAlignment = Alignment.Center,
                            label = "hero-bounce-landscape",
                        ) { showEncouragement ->
                            if (showEncouragement) {
                                Text(
                                    text = glowText(encouragement ?: ""),
                                    color = Color(0xFF6BC89B),
                                    fontSize = encourageFontSize,
                                    fontWeight = FontWeight.Medium,
                                    fontFamily = TimerFontFamily,
                                    letterSpacing = (-0.03).em,
                                    textAlign = TextAlign.Center,
                                    modifier = Modifier.fillMaxWidth(),
                                )
                            } else {
                                Text(
                                    text = timerText(sess.elapsedDisplay),
                                    textAlign = TextAlign.Center,
                                    style = TextStyle(
                                        color = Color(0xFFE8E4DF),
                                        fontSize = timerFontSize,
                                        fontWeight = FontWeight.SemiBold,
                                        fontFamily = TimerFontFamily,
                                        lineHeight = timerFontSize,
                                        letterSpacing = (-0.03).em,
                                        fontFeatureSettings = "tnum",
                                    ),
                                    modifier = Modifier.clickable(
                                        enabled = isManual && pgm.running,
                                        interactionSource = remember { MutableInteractionSource() },
                                        indication = null,
                                    ) { onDurationEditToggle(); haptic(context, 10) },
                                )
                            }
                        }
                    }
                }
            }

            MetricsRow(viewModel = viewModel, scale = metricsScale)

            // HUD (left) + speed/incline controls (right) — aligned top/bottom
            Row(modifier = Modifier.weight(1f)) {
                // HUD / Complete / Idle
                Box(modifier = Modifier.weight(1f).fillMaxHeight()) {
                    when {
                        pgm.program != null && pgm.running -> ProgramHUD(viewModel = viewModel, modifier = Modifier.fillMaxSize())
                        pgm.completed -> ProgramComplete(
                            viewModel = viewModel,
                            onVoice = { haptic(context, 20); onVoiceToggle(null) },
                        )
                        else -> IdleCard(
                            viewModel = viewModel,
                            onVoice = { prompt -> haptic(context, 20); onVoiceToggle(prompt) },
                            modifier = Modifier.fillMaxSize(),
                        )
                    }
                }

                // Speed/incline controls — vertical padding matches ProgramHUD's internal padding
                SpeedInclineControls(
                    viewModel = viewModel,
                    vertical = true,
                    fillHeight = true,
                    modifier = Modifier
                        .width(controlsWidth)
                        .fillMaxHeight()
                        .padding(end = 8.dp, top = 6.dp, bottom = 6.dp),
                )
            }

            // Stop/Resume spans full width below HUD + controls
            BottomBar(viewModel = viewModel, showControls = false)
        }
    }
}

@Composable
private fun DurationButton(
    deltaMinutes: Int,
    onClick: () -> Unit,
) {
    Box(
        modifier = Modifier
            .height(36.dp)
            .background(
                color = Color(0xFF1E1D1B),
                shape = RoundedCornerShape(9999.dp),
            )
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                onClick = onClick,
            )
            .padding(horizontal = 14.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = "${if (deltaMinutes > 0) "+" else ""}${deltaMinutes}m",
            color = if (deltaMinutes > 0) Color(0xFF6BC89B) else Color(0x59E8E4DF),
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold,
        )
    }
}
