/// 会话模型
class Session {
  const Session({
    required this.id,
    required this.serverId,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.messageCount = 0,
    this.lastMessagePreview = '',
    this.unreadCount = 0,
    this.isOnline = false,
  });

  final String id;
  final String serverId;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int messageCount;
  final String lastMessagePreview;
  final int unreadCount;
  final bool isOnline;

  Session copyWith({
    String? id,
    String? serverId,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? messageCount,
    String? lastMessagePreview,
    int? unreadCount,
    bool? isOnline,
  }) {
    return Session(
      id: id ?? this.id,
      serverId: serverId ?? this.serverId,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      messageCount: messageCount ?? this.messageCount,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
      unreadCount: unreadCount ?? this.unreadCount,
      isOnline: isOnline ?? this.isOnline,
    );
  }
}
