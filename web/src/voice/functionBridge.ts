/**
 * Forwards Gemini function calls to the server via /api/tool.
 *
 * All tool execution lives in server.py's _exec_fn() — the single source of
 * truth. This bridge just forwards the call and returns the result.
 */
import * as api from '../state/api';

export interface FunctionCall {
  name: string;
  args: Record<string, unknown>;
  context?: string;  // why the tool was called (model text, user utterance)
}

export interface FunctionResult {
  name: string;
  response: { result: string };
}

/** Execute a Gemini function call via the server's /api/tool endpoint. */
export async function executeFunctionCall(call: FunctionCall): Promise<FunctionResult> {
  const { name, args } = call;
  let result: string;

  try {
    const tr = await api.execTool(name, args, call.context);
    result = tr.ok ? (tr.result ?? 'Done') : `Error: ${tr.error ?? 'unknown'}`;
  } catch (err) {
    result = `Error executing ${name}: ${err instanceof Error ? err.message : String(err)}`;
  }

  return {
    name,
    response: { result },
  };
}
