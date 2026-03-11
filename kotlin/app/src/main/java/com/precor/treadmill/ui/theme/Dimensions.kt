package com.precor.treadmill.ui.theme

import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

object Touch {
    const val FINGERTIP_MM = 12f
    const val FINGER_PAD_MM = 16f
    const val THUMB_PAD_MM = 20f

    @Composable
    fun mmToHorizontalDp(mm: Float): Dp {
        val metrics = LocalContext.current.resources.displayMetrics
        return ((mm / 25.4f) * metrics.xdpi / metrics.density).dp
    }

    @Composable
    fun mmToVerticalDp(mm: Float): Dp {
        val metrics = LocalContext.current.resources.displayMetrics
        return ((mm / 25.4f) * metrics.ydpi / metrics.density).dp
    }
}

/** Chevron button width (12mm, horizontal axis) */
@Composable
fun touchFingertip(): Dp = Touch.mmToHorizontalDp(Touch.FINGERTIP_MM)

/** Button height for repeated presses (16mm, vertical axis) */
@Composable
fun touchFingerPad(): Dp = Touch.mmToVerticalDp(Touch.FINGER_PAD_MM)

/** Stop button height — largest target (20mm, vertical axis) */
@Composable
fun touchThumbPad(): Dp = Touch.mmToVerticalDp(Touch.THUMB_PAD_MM)
