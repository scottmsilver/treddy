package com.precor.treadmill.voice

import android.util.Log
import com.precor.treadmill.data.remote.TreadmillApi
import com.precor.treadmill.data.remote.models.ToolCallRequest
import kotlinx.serialization.json.JsonElement

/**
 * Forwards Gemini function calls to the server via /api/tool.
 *
 * All tool execution lives in server.py's _exec_fn() — the single source of
 * truth. This bridge just forwards the call and returns the result.
 */
class FunctionBridge(private val api: TreadmillApi) {

    companion object {
        private const val TAG = "FunctionBridge"
    }

    data class FunctionResult(
        val name: String,
        val response: String,
    )

    suspend fun execute(name: String, args: Map<String, JsonElement>, context: String? = null): FunctionResult {
        val result = try {
            val resp = api.execTool(ToolCallRequest(name, args, context))
            if (resp.ok) resp.result ?: "Done" else "Error: ${resp.error ?: "unknown"}"
        } catch (e: Exception) {
            Log.e(TAG, "Error executing $name", e)
            "Error executing $name: ${e.message}"
        }

        return FunctionResult(name = name, response = result)
    }
}
