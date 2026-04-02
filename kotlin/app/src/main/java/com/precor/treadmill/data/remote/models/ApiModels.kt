package com.precor.treadmill.data.remote.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement

// --- Request models ---

@Serializable
data class SpeedRequest(val value: Double)

@Serializable
data class InclineRequest(val value: Double)

@Serializable
data class EmulateRequest(val enabled: Boolean)

@Serializable
data class ProxyRequest(val enabled: Boolean)

@Serializable
data class GenerateRequest(val prompt: String)

@Serializable
data class QuickStartRequest(
    val speed: Double = 3.0,
    val incline: Double = 0.0,
    @SerialName("duration_minutes") val durationMinutes: Int = 60,
)

@Serializable
data class AdjustDurationRequest(
    @SerialName("delta_seconds") val deltaSeconds: Int,
)

@Serializable
data class ExtendRequest(val seconds: Int)

@Serializable
data class ChatRequest(
    val message: String,
    val smartass: Boolean = false,
)

@Serializable
data class VoiceChatRequest(
    val audio: String,
    @SerialName("mime_type") val mimeType: String,
    val smartass: Boolean = false,
)

@Serializable
data class ExtractIntentRequest(
    val text: String,
    @SerialName("already_executed") val alreadyExecuted: List<String> = emptyList(),
)

@Serializable
data class TtsRequest(
    val text: String,
    val voice: String = "Kore",
)

@Serializable
data class ToolCallRequest(
    val name: String,
    val args: Map<String, kotlinx.serialization.json.JsonElement> = emptyMap(),
    val context: String? = null,
)

@Serializable
data class ToolCallResponse(
    val ok: Boolean,
    val result: String? = null,
    val error: String? = null,
)

@Serializable
data class HrmSelectRequest(val address: String)

@Serializable
data class HrmStatusResponse(
    @SerialName("heart_rate") val heartRate: Int = 0,
    val connected: Boolean = false,
    val device: String = "",
    @SerialName("available_devices") val availableDevices: List<HrmDevice> = emptyList(),
)

// --- Response models ---

@Serializable
data class GenericOkResponse(
    val ok: Boolean,
    val error: String? = null,
)

@Serializable
data class GenerateResponse(
    val ok: Boolean,
    val program: Program? = null,
    val error: String? = null,
)

@Serializable
data class LoadHistoryResponse(
    val ok: Boolean,
    val program: Program? = null,
    val error: String? = null,
)

@Serializable
data class GpxUploadResponse(
    val ok: Boolean,
    val program: Program? = null,
    val error: String? = null,
)

@Serializable
data class ChatAction(
    val name: String = "",
    val args: Map<String, JsonElement> = emptyMap(),
    val result: String = "",
)

@Serializable
data class ChatResponse(
    val text: String = "",
    val actions: List<ChatAction> = emptyList(),
    val transcription: String? = null,
)

@Serializable
data class ExtractIntentResponse(
    val actions: List<ChatAction> = emptyList(),
    val text: String = "",
)

@Serializable
data class RunRecord(
    val id: String = "",
    @SerialName("started_at") val startedAt: String? = null,
    @SerialName("ended_at") val endedAt: String? = null,
    val elapsed: Double = 0.0,
    val distance: Double = 0.0,
    @SerialName("vert_feet") val vertFeet: Double = 0.0,
    @SerialName("end_reason") val endReason: String = "",
    @SerialName("program_name") val programName: String? = null,
    @SerialName("program_completed") val programCompleted: Boolean = false,
    @SerialName("is_manual") val isManual: Boolean = false,
)

@Serializable
data class HistoryEntry(
    val id: String = "",
    val prompt: String = "",
    val program: Program? = null,
    @SerialName("created_at") val createdAt: String = "",
    @SerialName("total_duration") val totalDuration: Double = 0.0,
    val completed: Boolean = false,
    @SerialName("last_interval") val lastInterval: Int = 0,
    @SerialName("last_elapsed") val lastElapsed: Int = 0,
    val saved: Boolean = false,
    @SerialName("last_run") val lastRun: RunRecord? = null,
    @SerialName("last_run_text") val lastRunText: String = "",
)

@Serializable
data class SavedWorkout(
    val id: String = "",
    val name: String = "",
    val program: Program? = null,
    @SerialName("created_at") val createdAt: String = "",
    val source: String = "",
    val prompt: String = "",
    @SerialName("times_used") val timesUsed: Int = 0,
    @SerialName("last_used") val lastUsed: String? = null,
    @SerialName("total_duration") val totalDuration: Int = 0,
    @SerialName("last_run") val lastRun: RunRecord? = null,
    @SerialName("last_run_text") val lastRunText: String = "",
    @SerialName("usage_text") val usageText: String = "",
)

@Serializable
data class SaveWorkoutRequest(
    @SerialName("history_id") val historyId: String? = null,
    val program: Program? = null,
    val source: String? = null,
    val prompt: String? = null,
)

@Serializable
data class SaveWorkoutResponse(
    val ok: Boolean,
    val workout: SavedWorkout? = null,
    val error: String? = null,
)

@Serializable
data class RenameWorkoutRequest(val name: String)

@Serializable
data class AppConfig(
    @SerialName("gemini_api_key") val geminiApiKey: String = "",
    @SerialName("gemini_model") val geminiModel: String = "",
    @SerialName("gemini_live_model") val geminiLiveModel: String = "",
    @SerialName("gemini_voice") val geminiVoice: String = "",
    @SerialName("tools") val tools: kotlinx.serialization.json.JsonArray? = null,
    @SerialName("system_prompt") val systemPrompt: String? = null,
    @SerialName("smartass_addendum") val smartassAddendum: String? = null,
)

@Serializable
data class LogResponse(val lines: List<String>)

@Serializable
data class VoicePromptResponse(val prompt: String)

@Serializable
data class UserProfile(
    val id: String = "1",
    @SerialName("weight_lbs") val weightLbs: Int = 154,
    @SerialName("vest_lbs") val vestLbs: Int = 0,
)

@Serializable
data class UpdateUserRequest(
    @SerialName("weight_lbs") val weightLbs: Int? = null,
    @SerialName("vest_lbs") val vestLbs: Int? = null,
)

@Serializable
data class TtsResponse(
    val ok: Boolean,
    val audio: String? = null,
    @SerialName("sample_rate") val sampleRate: Int? = null,
    val error: String? = null,
)
