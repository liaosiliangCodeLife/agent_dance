# Hermes API Server — 接口协议

> 定义 Flutter App 与 Hermes Agent API Server 之间的 HTTP 协议。
> Hermes 通过端口映射暴露，App 侧视为本地访问 (`http://localhost:8642`)。

---

## 1. 端点

| 方法 | 路径 | 说明 |
|------|------|------|
| `GET` | `/health` | 健康检查 |
| `POST` | `/v1/chat/completions` | 对话补全（支持流式） |

---

## 2. 通用规范

### 认证

```
Authorization: Bearer ***
C...ype: application/json
```

### 超时

| 类型 | 超时 |
|------|------|
| `/health` | 5s |
| 非流式 chat | 120s |
| 流式 chat（连接建立） | 30s |
| 流式 chat（读取空闲） | 300s |

---

## 3. GET /health

**响应 200：**
```json
{"status": "ok"}
```

---

## 4. POST /v1/chat/completions

### 4.1 请求

```json
{
  "model": "hermes-agent",
  "messages": [
    {"role": "system", "content": "你用中文回答，简洁高效。"},
    {"role": "user",   "content": "帮我查广州天气"}
  ],
  "stream": false
}
```

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `model` | string | ✅ | 固定 `"hermes-agent"` |
| `messages` | array | ✅ | 完整对话历史（system + user + assistant 交替） |
| `messages[].role` | string | ✅ | `"system"` / `"user"` / `"assistant"` |
| `messages[].content` | string 或 array | ✅ | 纯文本；或 content 数组传图片（见第 6 节） |
| `stream` | boolean | ❌ | 默认 `false`。`true` 时返回 SSE 流 |

### 4.2 非流式响应

```json
{
  "id": "chatcmpl-xxx",
  "object": "chat.completion",
  "model": "hermes-agent",
  "choices": [{
    "index": 0,
    "message": {
      "role": "assistant",
      "content": "今天广州：多云转晴，26°C~33°C ☀️",
      "reasoning_content": "用户想知道广州今天天气..."
    },
    "finish_reason": "stop"
  }],
  "usage": {"prompt_tokens": 30, "completion_tokens": 80, "total_tokens": 110}
}
```

> `content` 可以是**纯文本字符串**，也可以是**数组**（多模态输出时）：
> ```json
> "content": [
>   {"type": "text", "text": "这是生成的图片："},
>   {"type": "image_url", "image_url": {"url": "data:image/png;base64,iVBORw0..."}}
> ]
> ```
> App 端需同时解析两种格式。当 `content` 是数组时，`text` 部分用 Markdown 渲染，`image_url` 部分显示图片。

### 4.3 流式响应 (stream=true)

SSE 协议，`Content-Type: text/event-stream`。

#### Chunk JSON 完整结构

```json
{
  "id": "chatcmpl-xxx",
  "object": "chat.completion.chunk",
  "choices": [{
    "index": 0,
    "delta": {
      "role": "assistant",
      "content": "文本片段",
      "reasoning_content": "思考过程片段"
    },
    "finish_reason": null
  }]
}
```

对应的 Dart 映射：

```dart
class ChatChunk {
  final String id;
  final String object;
  final List<ChunkChoice> choices;
}
class ChunkChoice {
  final int index;
  final ChunkDelta delta;
  final String? finishReason;   // null → "stop"
}
class ChunkDelta {
  final String? role;               // 仅第一个 chunk 有 "assistant"
  final String? content;            // 正文 token
  final String? reasoningContent;   // 思考过程 token（DeepSeek 等模型）
}
```

#### 4.3.1 思考过程 (reasoning_content) 的流式时序

部分模型（DeepSeek-R1/V3 等）会**先输出全部 `reasoning_content`，再输出 `content`**。典型时序：

```
# 阶段 1：思考过程
data: {"choices":[{"delta":{"reasoning_content":"好的"},"finish_reason":null}]}
data: {"choices":[{"delta":{"reasoning_content":"，用户"},"finish_reason":null}]}
data: {"choices":[{"delta":{"reasoning_content":"想知道广州"},"finish_reason":null}]}
data: {"choices":[{"delta":{"reasoning_content":"天气"},"finish_reason":null}]}

# 阶段 2：正式回答
data: {"choices":[{"delta":{"content":"今天"},"finish_reason":null}]}
data: {"choices":[{"delta":{"content":"广州天气"},"finish_reason":null}]}

data: [DONE]
```

> **注意**：一个 chunk 可能出现 `reasoning_content` 和 `content` 同时为空的情况（纯心跳），客户端应忽略。

#### 4.3.2 工具进度事件（自定义）

```
event: hermes.tool.progress
data: {"tool":"web_search","status":"running","message":"正在搜索天气信息..."}
```

#### 4.3.3 指令执行审批（Runs API）

当 Hermes 检测到危险指令需用户批准时，通过 **Runs API** 推送 `approval.request` 事件（Chat Completions 流不含此事件，App 文本对话应优先走 Runs API）。

**启动 run：**
```
POST /v1/runs
Header: X-Hermes-Session-Key: <稳定会话键>
Body: {"input":"用户消息","conversation_history":[...],"session_id":"..."}
→ 202 {"run_id":"run_xxx","status":"started"}
```

**订阅事件：**
```
GET /v1/runs/{run_id}/events  (SSE)
data: {"event":"approval.request","run_id":"run_xxx","command":"rm -rf ...","description":"...","choices":["once","session","always","deny"]}
data: {"event":"message.delta","delta":"回复片段"}
data: {"event":"reasoning.available","text":"思考过程片段"}
data: {"event":"run.completed","output":"..."}
```

**提交审批：**
```
POST /v1/runs/{run_id}/approval
Body: {"choice":"once"}   // once | session | always | deny
```

App 行为：弹出确认框，**60 秒无操作自动 `choice: once`**。

#### 4.3.4 SSE 解析完整规则

```dart
// 伪代码 — 流式行级解析
String? currentEvent;

for (line in lines) {
  if (line.isEmpty) { currentEvent = null; continue; }

  if (line.startsWith('event: ')) {
    currentEvent = line.substring(7).trim();
    continue;
  }

  if (!line.startsWith('data: ')) continue;

  final data = line.substring(6);
  if (data == '[DONE]') { yield SseDone(); break; }

  // 工具进度事件
  if (currentEvent == 'hermes.tool.progress') {
    final tool = jsonDecode(data);
    yield SseToolProgress(message: tool['message']);
    currentEvent = null;
    continue;
  }

  // 标准 chunk
  final chunk = ChatChunk.fromJson(jsonDecode(data));
  final delta = chunk.choices.firstOrNull?.delta;
  if (delta == null) continue;

  if ((delta.reasoningContent ?? '').isNotEmpty) {
    yield SseReasoning(text: delta.reasoningContent!);
  }
  if ((delta.content ?? '').isNotEmpty) {
    yield SseToken(text: delta.content!);
  }
}
```

#### 4.3.5 SSE 事件类型汇总

```dart
sealed class SseEvent {}
class SseReasoning     extends SseEvent { final String text; }   // 思考过程
class SseToken         extends SseEvent { final String text; }   // 正文
class SseToolProgress  extends SseEvent { final String message; } // 工具进度
class SseApprovalRequest extends SseEvent { ... }               // 指令审批（Runs API）
class SseDone          extends SseEvent {}                       // 流结束
```

---

## 5. 语音消息 — Hermes STT

App 录音后将音频 base64 编码，随请求发给 Hermes。Hermes Gateway 端的 STT 引擎（`stt.enabled: true`，如 faster-whisper）自动转录为文本后交给 Agent 处理。

**前置条件（Hermes 服务端）：**
```yaml
# ~/.hermes/config.yaml
stt:
  enabled: true
  provider: local           # local (faster-whisper) / groq / openai / mistral
  local:
    model: base             # tiny / base / small / medium / large-v3
```

**请求格式：**
```json
{
  "model": "hermes-agent",
  "messages": [{
    "role": "user",
    "content": [
      {"type": "text", "text": "帮我总结这段录音内容"},
      {"type": "input_audio", "input_audio": {
        "data": "base64编码的音频数据（不含 data: 前缀）",
        "format": "m4a"
      }}
    ]
  }]
}
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `content[].type` | string | ✅ | `"text"` 或 `"input_audio"` |
| `input_audio.data` | string | ✅ | 纯 base64，**不含** `data:audio/xxx;base64,` 前缀 |
| `input_audio.format` | string | ✅ | `"m4a"` / `"mp3"` / `"wav"` |

**App 端流程**：
```
按住录音 → .m4a 文件（≤ 60s）
         → base64 编码（去掉 data: 前缀）
         → 拼入 content 数组 [{text},{input_audio}]
         → POST /v1/chat/completions
         → Hermes STT 引擎转录 → 文本注入 Agent
         → Agent 处理 → 流式返回回复
```

**约束**：
- 录音格式：M4A (AAC)，单声道 16kHz
- 时长限制：≤ 60 秒
- 文件限制：≤ 5MB（base64 编码前）
- 同一条消息可同时包含文字和语音（文字作为附言/指令）

---

## 6. 图片输入

```json
{
  "model": "hermes-agent",
  "messages": [{
    "role": "user",
    "content": [
      {"type": "text", "text": "图片里有什么？"},
      {"type": "image_url", "image_url": {"url": "data:image/jpeg;base64,/9j/4AAQ..."}}
    ]
  }]
}
```

**约束**：
- base64 前缀：`data:image/jpeg;base64,` 或 `data:image/png;base64,`
- JPEG 压缩到最长边 ≤ 2048px，文件 ≤ 2MB 再编码
- 支持 jpeg / png / webp
- 无需 `stream` 特殊处理，流式返回同文本流程

---

## 7. 错误响应

| 状态码 | body | App 处理 |
|--------|------|----------|
| 401 | `{"error":{"message":"Invalid API key"}}` | 提示重新配置 |
| 429 | `{"error":{"message":"Too many requests"}}` | sleep 3s 重试一次 |
| 500 | `{"error":{"message":"Internal server error"}}` | 提示"服务暂不可用" |
| 网络不通 | 无响应 | 提示"无法连接服务器" |

---

*文档版本: v2.1*
*日期: 2026-06-12*
