package com.precor.treadmill.ui.screens.running

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.width
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.unit.DpRect
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class NextChangeValueRowTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun minuteAndHourClocksStayOnOneUntruncatedBaselineRow() {
        assertOneLineLayout("59:59", "1:00:00")
    }

    @Test
    fun hourClocksStayOnOneUntruncatedBaselineRow() {
        assertOneLineLayout("1:00:00", "12:34:56")
    }

    private fun assertOneLineLayout(timeUntilText: String, timerAtChangeText: String) {
        composeRule.setContent {
            Box(Modifier.width(180.dp)) {
                NextChangeValueRow(timeUntilText, timerAtChangeText)
            }
        }

        val row = composeRule.onNodeWithTag(NEXT_CHANGE_VALUE_ROW_TAG).getUnclippedBoundsInRoot()
        val timeUntil = composeRule.onNodeWithTag(NEXT_CHANGE_TIME_UNTIL_TAG)
        val at = composeRule.onNodeWithTag(NEXT_CHANGE_AT_TAG)
        val timerAtChange = composeRule.onNodeWithTag(NEXT_CHANGE_TIMER_AT_CHANGE_TAG)
        val timeUntilBounds = timeUntil.getUnclippedBoundsInRoot()
        val atBounds = at.getUnclippedBoundsInRoot()
        val timerAtChangeBounds = timerAtChange.getUnclippedBoundsInRoot()

        timeUntil.assertIsDisplayed().assertTextEquals(timeUntilText)
        at.assertIsDisplayed().assertTextEquals("at")
        timerAtChange.assertIsDisplayed().assertTextEquals(timerAtChangeText)
        assertOrderedAndContained(row, timeUntilBounds, atBounds, timerAtChangeBounds)
        listOf(
            NEXT_CHANGE_TIME_UNTIL_TAG to timeUntil,
            NEXT_CHANGE_AT_TAG to at,
            NEXT_CHANGE_TIMER_AT_CHANGE_TAG to timerAtChange,
        ).forEach { (tag, node) ->
            val results = mutableListOf<TextLayoutResult>()
            node.performSemanticsAction(SemanticsActions.GetTextLayoutResult) { action ->
                action(results)
            }
            val result = results.single()
            assertEquals("$tag text=${result.layoutInput.text.text}", 1, result.lineCount)
            assertFalse(
                "$tag text=${result.layoutInput.text.text} size=${result.size} " +
                    "didOverflowWidth=${result.didOverflowWidth} " +
                    "didOverflowHeight=${result.didOverflowHeight} " +
                    "paragraph=${result.multiParagraph.width}x${result.multiParagraph.height} " +
                    "constraints=${result.layoutInput.constraints}",
                result.hasVisualOverflow,
            )
        }
    }

    private fun assertOrderedAndContained(row: DpRect, first: DpRect, second: DpRect, third: DpRect) {
        assertTrue(first.right <= second.left)
        assertTrue(second.right <= third.left)
        assertTrue(first.overlapsVertically(second))
        assertTrue(second.overlapsVertically(third))
        listOf(first, second, third).forEach { text ->
            assertTrue(text.left >= row.left)
            assertTrue(text.right <= row.right)
            assertTrue(text.top >= row.top)
            assertTrue(text.bottom <= row.bottom)
        }
    }

    private fun DpRect.overlapsVertically(other: DpRect): Boolean =
        top < other.bottom && bottom > other.top
}
