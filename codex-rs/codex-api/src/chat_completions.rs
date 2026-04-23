//! Translates between the Responses API wire format and the Chat Completions API format.
//!
//! When a provider only supports `/v1/chat/completions`, this module handles:
//! 1. Converting a `ResponsesApiRequest` (serialized as JSON) into a Chat Completions request body
//! 2. Processing the Chat Completions SSE stream and emitting `ResponseEvent` values

use crate::common::ResponseEvent;
use crate::error::ApiError;
use codex_client::ByteStream;
use codex_client::StreamResponse;
use codex_protocol::models::ResponseItem;
use eventsource_stream::Eventsource;
use futures::StreamExt;
use serde::Deserialize;
use serde_json::Value;
use std::collections::HashMap;
use std::time::Duration;
use tokio::sync::mpsc;
use tokio::time::timeout;
use tracing::debug;
use tracing::trace;

use crate::common::ResponseStream;

/// Translate a serialized `ResponsesApiRequest` JSON value into a Chat Completions request body.
pub fn responses_to_chat_completions(responses_body: &Value) -> Value {
    let mut messages = Vec::new();

    if let Some(instructions) = responses_body.get("instructions").and_then(|v| v.as_str())
        && !instructions.is_empty()
    {
        messages.push(serde_json::json!({
            "role": "system",
            "content": instructions
        }));
    }

    if let Some(input) = responses_body.get("input").and_then(|v| v.as_array()) {
        for item in input {
            if let Some(msg) = translate_input_item(item) {
                messages.push(msg);
            }
        }
    }

    let tools: Option<Vec<Value>> = responses_body
        .get("tools")
        .and_then(|v| v.as_array())
        .map(|tools| {
            tools
                .iter()
                .filter_map(|t| {
                    if t.get("type").and_then(|v| v.as_str()) == Some("function") {
                        Some(t.clone())
                    } else {
                        None
                    }
                })
                .collect()
        })
        .filter(|t: &Vec<Value>| !t.is_empty());

    let mut body = serde_json::json!({
        "model": responses_body.get("model").cloned().unwrap_or(Value::Null),
        "messages": messages,
        "stream": true
    });

    if let Some(tools) = tools {
        body["tools"] = Value::Array(tools);
        body["tool_choice"] = serde_json::json!("auto");
    }

    if let Some(reasoning) = responses_body.get("reasoning") {
        body["reasoning"] = reasoning.clone();
    }

    body
}

fn translate_input_item(item: &Value) -> Option<Value> {
    match item.get("type").and_then(|v| v.as_str()) {
        Some("message") => {
            let role = item.get("role").and_then(|v| v.as_str()).unwrap_or("user");
            let content = translate_content(item.get("content"));
            Some(serde_json::json!({ "role": role, "content": content }))
        }
        Some("function_call_output") => {
            let call_id = item.get("call_id").and_then(|v| v.as_str()).unwrap_or("");
            let output = extract_output_text(item);
            Some(serde_json::json!({
                "role": "tool",
                "tool_call_id": call_id,
                "content": output
            }))
        }
        Some("function_call") => {
            let call_id = item.get("call_id").and_then(|v| v.as_str()).unwrap_or("");
            let name = item.get("name").and_then(|v| v.as_str()).unwrap_or("");
            let arguments = item
                .get("arguments")
                .and_then(|v| v.as_str())
                .unwrap_or("{}");
            Some(serde_json::json!({
                "role": "assistant",
                "tool_calls": [{
                    "id": call_id,
                    "type": "function",
                    "function": { "name": name, "arguments": arguments }
                }]
            }))
        }
        _ => {
            if let Some(role) = item.get("role").and_then(|v| v.as_str()) {
                let content = translate_content(item.get("content"));
                Some(serde_json::json!({ "role": role, "content": content }))
            } else {
                None
            }
        }
    }
}

fn translate_content(content: Option<&Value>) -> Value {
    match content {
        Some(Value::Array(items)) => {
            let parts: Vec<Value> = items
                .iter()
                .filter_map(|item| match item.get("type").and_then(|v| v.as_str()) {
                    Some("input_text") | Some("output_text") => {
                        let text = item.get("text").and_then(|v| v.as_str()).unwrap_or("");
                        Some(serde_json::json!({"type": "text", "text": text}))
                    }
                    Some("input_image") => {
                        let url = item.get("image_url").and_then(|v| v.as_str()).unwrap_or("");
                        Some(serde_json::json!({
                            "type": "image_url",
                            "image_url": {"url": url}
                        }))
                    }
                    _ => None,
                })
                .collect();
            if parts.len() == 1
                && let Some(text) = parts[0].get("text")
            {
                return text.clone();
            }
            Value::Array(parts)
        }
        Some(v) => v.clone(),
        None => Value::Null,
    }
}

fn extract_output_text(item: &Value) -> String {
    if let Some(output) = item.get("output") {
        match output {
            Value::String(s) => return s.clone(),
            Value::Object(obj) => {
                if let Some(content) = obj.get("content").and_then(|v| v.as_str()) {
                    return content.to_string();
                }
            }
            _ => {}
        }
    }
    String::new()
}

// --- SSE response processing ---

#[derive(Debug, Deserialize)]
struct ChatCompletionChunk {
    id: Option<String>,
    choices: Vec<ChatCompletionChoice>,
}

#[derive(Debug, Deserialize)]
struct ChatCompletionChoice {
    delta: ChatCompletionDelta,
    finish_reason: Option<String>,
}

#[derive(Debug, Deserialize, Default)]
struct ChatCompletionDelta {
    content: Option<String>,
    tool_calls: Option<Vec<ChatCompletionToolCall>>,
}

#[derive(Debug, Deserialize, Clone)]
struct ChatCompletionToolCall {
    index: Option<usize>,
    id: Option<String>,
    function: Option<ChatCompletionFunction>,
}

#[derive(Debug, Deserialize, Clone)]
struct ChatCompletionFunction {
    name: Option<String>,
    arguments: Option<String>,
}

/// Spawn a task that processes a Chat Completions SSE byte stream and produces `ResponseEvent`s.
pub fn spawn_chat_completions_stream(
    stream_response: StreamResponse,
    idle_timeout: Duration,
) -> ResponseStream {
    let (tx_event, rx_event) = mpsc::channel::<Result<ResponseEvent, ApiError>>(1600);
    tokio::spawn(process_chat_completions_sse(
        stream_response.bytes,
        tx_event,
        idle_timeout,
    ));
    ResponseStream { rx_event }
}

async fn process_chat_completions_sse(
    stream: ByteStream,
    tx: mpsc::Sender<Result<ResponseEvent, ApiError>>,
    idle_timeout: Duration,
) {
    let mut stream = stream.eventsource();
    let mut response_id = String::from("resp_chat");
    // Track accumulated tool calls: index -> (id, name, arguments)
    let mut tool_calls: HashMap<usize, (String, String, String)> = HashMap::new();

    loop {
        let response = timeout(idle_timeout, stream.next()).await;
        let sse = match response {
            Ok(Some(Ok(sse))) => sse,
            Ok(Some(Err(e))) => {
                debug!("Chat completions SSE error: {e:#}");
                let _ = tx.send(Err(ApiError::Stream(e.to_string()))).await;
                return;
            }
            Ok(None) => {
                // Stream ended - emit completed if we haven't already
                emit_completed(&tx, &response_id, &mut tool_calls).await;
                return;
            }
            Err(_) => {
                let _ = tx
                    .send(Err(ApiError::Stream("idle timeout waiting for SSE".into())))
                    .await;
                return;
            }
        };

        if sse.data == "[DONE]" {
            emit_completed(&tx, &response_id, &mut tool_calls).await;
            return;
        }

        trace!("Chat completions SSE: {}", &sse.data);

        let chunk: ChatCompletionChunk = match serde_json::from_str(&sse.data) {
            Ok(c) => c,
            Err(e) => {
                debug!(
                    "Failed to parse chat completion chunk: {e}, data: {}",
                    &sse.data
                );
                continue;
            }
        };

        if let Some(id) = &chunk.id {
            response_id = id.clone();
        }

        for choice in &chunk.choices {
            // Text content
            if let Some(content) = &choice.delta.content
                && !content.is_empty()
                && tx
                    .send(Ok(ResponseEvent::OutputTextDelta(content.clone())))
                    .await
                    .is_err()
            {
                return;
            }

            // Tool calls
            if let Some(tcs) = &choice.delta.tool_calls {
                for tc in tcs {
                    let idx = tc.index.unwrap_or(0);
                    let entry = tool_calls.entry(idx).or_insert_with(|| {
                        (
                            tc.id.clone().unwrap_or_default(),
                            String::new(),
                            String::new(),
                        )
                    });
                    if let Some(id) = &tc.id
                        && !id.is_empty()
                    {
                        entry.0 = id.clone();
                    }
                    if let Some(func) = &tc.function {
                        if let Some(name) = &func.name {
                            entry.1 = name.clone();
                        }
                        if let Some(args) = &func.arguments {
                            entry.2.push_str(args);
                        }
                    }
                }
            }

            // Finish reason
            if let Some(reason) = &choice.finish_reason {
                match reason.as_str() {
                    "stop" => {
                        emit_completed(&tx, &response_id, &mut tool_calls).await;
                        return;
                    }
                    "tool_calls" => {
                        emit_completed(&tx, &response_id, &mut tool_calls).await;
                        return;
                    }
                    _ => {}
                }
            }
        }
    }
}

async fn emit_completed(
    tx: &mpsc::Sender<Result<ResponseEvent, ApiError>>,
    response_id: &str,
    tool_calls: &mut HashMap<usize, (String, String, String)>,
) {
    // Emit accumulated tool calls as OutputItemDone
    for (_idx, (call_id, name, arguments)) in tool_calls.drain() {
        if !name.is_empty() {
            let item = ResponseItem::FunctionCall {
                id: None,
                name,
                namespace: None,
                arguments,
                call_id,
            };
            if tx
                .send(Ok(ResponseEvent::OutputItemDone(item)))
                .await
                .is_err()
            {
                return;
            }
        }
    }

    let _ = tx
        .send(Ok(ResponseEvent::Completed {
            response_id: response_id.to_string(),
            token_usage: None,
        }))
        .await;
}
