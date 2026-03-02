package com.precor.treadmill.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.precor.treadmill.data.remote.TreadmillApi
import com.precor.treadmill.data.remote.models.HistoryEntry
import com.precor.treadmill.ui.theme.LocalPrecorColors
import com.precor.treadmill.ui.util.fmtDur
import kotlinx.coroutines.launch
import org.koin.compose.koinInject

@Composable
fun HistoryList(
    variant: String, // "lobby" or "compact"
    onAfterLoad: () -> Unit = {},
    modifier: Modifier = Modifier,
    api: TreadmillApi = koinInject(),
) {
    val colors = LocalPrecorColors.current
    val scope = rememberCoroutineScope()
    var history by remember { mutableStateOf<List<HistoryEntry>>(emptyList()) }

    LaunchedEffect(Unit) {
        runCatching { history = api.getHistory() }
    }

    val handleLoad: (String) -> Unit = { id ->
        scope.launch {
            runCatching {
                val res = api.loadFromHistory(id)
                if (res.ok) onAfterLoad()
            }
        }
    }

    val handleResume: (String) -> Unit = { id ->
        scope.launch {
            runCatching {
                api.resumeFromHistory(id)
                onAfterLoad()
            }
        }
    }

    if (variant == "lobby") {
        Column(
            modifier = modifier.padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            history.forEach { entry ->
                HistoryCard(
                    entry = entry,
                    variant = "lobby",
                    onLoad = handleLoad,
                    onResume = handleResume,
                )
            }
        }
    } else {
        if (history.isEmpty()) return

        Column(modifier = modifier) {
            Row(
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = "RECENT PROGRAMS",
                    color = colors.text3,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold,
                    letterSpacing = 0.3.sp,
                )
            }
            Row(
                modifier = Modifier
                    .horizontalScroll(rememberScrollState())
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                history.forEach { entry ->
                    HistoryCard(
                        entry = entry,
                        variant = "compact",
                        onLoad = handleLoad,
                        onResume = handleResume,
                    )
                }
            }
        }
    }
}

@Composable
private fun HistoryCard(
    entry: HistoryEntry,
    variant: String,
    onLoad: (String) -> Unit,
    onResume: (String) -> Unit = {},
) {
    val colors = LocalPrecorColors.current
    val name = entry.program.name.ifBlank { "Workout" }
    val intervals = entry.program.intervals.size
    val duration = fmtDur(entry.totalDuration.toInt())
    val canResume = !entry.completed && entry.lastElapsed > 0
    val resumeLabel = if (canResume) "Resume from ${fmtDur(entry.lastElapsed)}" else null
    val displayName = if (entry.completed) "$name \u2713" else name

    if (variant == "lobby") {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(
                    color = colors.card,
                    shape = MaterialTheme.shapes.medium,
                )
                .clickable { onLoad(entry.id) }
                .padding(12.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = displayName,
                    color = colors.text,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Spacer(Modifier.height(4.dp))
                Text(
                    text = "$duration \u00B7 $intervals intervals",
                    color = colors.text3,
                    fontSize = 12.sp,
                )
            }
            if (canResume) {
                Text(
                    text = resumeLabel ?: "",
                    color = colors.green,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier
                        .clickable { onResume(entry.id) }
                        .background(
                            color = colors.green.copy(alpha = 0.12f),
                            shape = MaterialTheme.shapes.small,
                        )
                        .padding(horizontal = 10.dp, vertical = 4.dp),
                )
            }
        }
    } else {
        Column(
            modifier = Modifier
                .width(140.dp)
                .background(
                    color = colors.card,
                    shape = MaterialTheme.shapes.medium,
                )
                .clickable { if (canResume) onResume(entry.id) else onLoad(entry.id) }
                .padding(12.dp),
        ) {
            Text(
                text = displayName,
                color = colors.text,
                fontSize = 13.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Spacer(Modifier.height(4.dp))
            Text(
                text = if (canResume) resumeLabel ?: "" else "$duration \u00B7 $intervals intervals",
                color = if (canResume) colors.green else colors.text3,
                fontSize = 11.sp,
            )
        }
    }
}
