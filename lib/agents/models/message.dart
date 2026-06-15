/// 聊天消息模型
class Message {
  const Message({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    this.reasoningText,
    this.imageBase64s,
    required this.createdAt,
    this.tokenCount = 0,
  });

  final String id;
  final String sessionId;
  final String role;
  final String content;
  final String? reasoningText;
  final List<String>? imageBase64s;
  final DateTime createdAt;
  final int tokenCount;

  bool get hasReasoning => reasoningText != null && reasoningText!.isNotEmpty;
  bool get hasImages => imageBase64s != null && imageBase64s!.isNotEmpty;
  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';

  Message copyWith({
    String? id,
    String? sessionId,
    String? role,
    String? content,
    String? reasoningText,
    List<String>? imageBase64s,
    DateTime? createdAt,
    int? tokenCount,
  }) {
    return Message(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      role: role ?? this.role,
      content: content ?? this.content,
      reasoningText: reasoningText ?? this.reasoningText,
      imageBase64s: imageBase64s ?? this.imageBase64s,
      createdAt: createdAt ?? this.createdAt,
      tokenCount: tokenCount ?? this.tokenCount,
    );
  }
}
