# Cursor 修复指令

## BUG 1：退出重进后上下文丢失

**症状**：App 内正常，退出重进后 `conversationHistory` 为空，Hermes 端上下文丢失。

**根因**：本地 DB 消息未持久化（App 被杀时异步写入丢失）+ 空 `conversation_history` 可能覆盖 Hermes 已有上下文。

### 修复 1：不传空 conversationHistory

`chat_repository.dart` `streamReply()` 中，将空数组改为不传该字段：

```dart
// startRun body 中
final body = <String, dynamic>{
  'input': userInputForRuns,
  'session_id': sessionId,
};
if (conversationHistory.isNotEmpty) {
  body['conversation_history'] = conversationHistory;
}
```

这样 Hermes 在没有 conversationHistory 时会从已有 session 恢复上下文，而不是被空数组覆盖。

### 修复 2：确保消息写入 DB 后 App 退出前 flush

在 `ChatViewModel.disposeInternal()` 中加 DB flush：

```dart
void disposeInternal() {
    ...
    // flush DB 确保消息持久化
    _chatRepository.db.flush();  // 或类似方法
}
```

如果 Drift 没有 flush，用 `await` 等待最后一次写入完成。

---

## BUG 2（已修复）：takeStreamingIncrement — 不要动

---

## 之前修复（已完成，不要回滚）

- `agents_api_client.dart:402` — run.completed 兜底
- `chat_screen.dart:309` — 流式渲染兜底
- `chat_viewmodel.dart:305` — 保存消息兜底
