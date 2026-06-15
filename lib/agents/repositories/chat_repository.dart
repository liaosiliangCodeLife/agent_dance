import 'package:agent_dance/agents/database/app_database.dart';
import 'package:agent_dance/agents/models/chat_state.dart';
import 'package:agent_dance/agents/models/message.dart';
import 'package:agent_dance/agents/models/server.dart';
import 'package:agent_dance/agents/models/session.dart';
import 'package:agent_dance/config/app_config.dart';
import 'package:agent_dance/protocol/agents_api_client.dart';
import 'package:agent_dance/utils/logger.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// 服务器 CRUD 与连通性检测
class ServerRepository {
  ServerRepository(this._db);

  final AppDatabase _db;
  final _log = Logger('ServerRepository');
  final _uuid = const Uuid();

  Future<List<AgentServer>> getAllServers() async {
    final rows = await _db.getAllServers();
    return rows.map(_mapServer).toList();
  }

  Future<AgentServer?> getServerById(String id) async {
    final row = await _db.getServerById(id);
    return row == null ? null : _mapServer(row);
  }

  Future<AgentServer> saveServer({
    String? id,
    required String name,
    required String host,
    required int port,
    required AgentType agentType,
    required String apiKey,
    String iconKey = 'emoji:🤖',
  }) async {
    final now = DateTime.now();
    final serverId = id ?? _uuid.v4();
    final existing = id != null ? await _db.getServerById(id) : null;
    await _db.upsertServer(
      ServersCompanion(
        id: Value(serverId),
        name: Value(name),
        host: Value(host),
        port: Value(port),
        agentType: Value(agentType.name),
        iconKey: Value(iconKey),
        createdAt: Value(existing?.createdAt ?? now.millisecondsSinceEpoch),
        updatedAt: Value(now.millisecondsSinceEpoch),
      ),
    );
    await AppConfig.writeServerApiKey(serverId, apiKey);
    _log.info('保存服务器', {'serverId': serverId, 'name': name});
    return AgentServer(
      id: serverId,
      name: name,
      host: host,
      port: port,
      agentType: agentType,
      iconKey: iconKey,
      createdAt: existing != null
          ? DateTime.fromMillisecondsSinceEpoch(existing.createdAt)
          : now,
      updatedAt: now,
    );
  }

  Future<void> deleteServer(String id) async {
    await AppConfig.deleteServerApiKey(id);
    await _db.deleteServer(id);
    _log.info('删除服务器', {'serverId': id});
  }

  Future<String?> getApiKey(String serverId) {
    return AppConfig.readServerApiKey(serverId);
  }

  Future<AgentsApiClient> createApiClient(String serverId) async {
    final server = await getServerById(serverId);
    if (server == null) {
      throw StateError('服务器不存在');
    }
    final apiKey = await getApiKey(serverId) ?? '';
    return AgentsApiClient(baseUrl: server.baseUrl, apiKey: apiKey);
  }

  Future<int?> testConnection({
    required String host,
    required int port,
    required String apiKey,
  }) async {
    final client = AgentsApiClient(
      baseUrl: AppConfig.buildBaseUrl(host, port),
      apiKey: apiKey,
    );
    return client.healthCheck();
  }

  Future<void> refreshServerStatus(String serverId) async {
    try {
      final client = await createApiClient(serverId);
      final latency = await client.healthCheck();
      await _db.updateServerStatus(serverId, latency != null, latency);
    } catch (e) {
      await _db.updateServerStatus(serverId, false, null);
    }
  }

  Future<void> refreshAllServerStatus() async {
    final servers = await getAllServers();
    for (final server in servers) {
      await refreshServerStatus(server.id);
    }
  }

  AgentServer _mapServer(Server row) {
    return AgentServer(
      id: row.id,
      name: row.name,
      host: row.host,
      port: row.port,
      agentType: AgentType.fromString(row.agentType),
      iconKey: row.iconKey,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row.updatedAt),
      isOnline: row.isOnline,
      latencyMs: row.latencyMs,
    );
  }
}

/// 会话 CRUD
class SessionRepository {
  SessionRepository(this._db);

  final AppDatabase _db;
  final _uuid = const Uuid();

  Future<List<Session>> getAllSessions() async {
    final rows = await _db.getAllSessions();
    final servers = await _db.getAllServers();
    final onlineMap = {for (final s in servers) s.id: s.isOnline};
    return rows
        .map(
          (row) => Session(
            id: row.id,
            serverId: row.serverId,
            title: row.title,
            createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
            updatedAt: DateTime.fromMillisecondsSinceEpoch(row.updatedAt),
            messageCount: row.messageCount,
            lastMessagePreview: row.lastMessagePreview,
            unreadCount: row.unreadCount,
            isOnline: onlineMap[row.serverId] ?? false,
          ),
        )
        .toList();
  }

  Future<Session?> getSessionById(String id) async {
    final row = await _db.getSessionById(id);
    if (row == null) {
      return null;
    }
    final server = await _db.getServerById(row.serverId);
    return Session(
      id: row.id,
      serverId: row.serverId,
      title: row.title,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row.updatedAt),
      messageCount: row.messageCount,
      lastMessagePreview: row.lastMessagePreview,
      unreadCount: row.unreadCount,
      isOnline: server?.isOnline ?? false,
    );
  }

  Future<Session> createSession({required String serverId, String? title}) async {
    final now = DateTime.now();
    final id = _uuid.v4();
    await _db.upsertSession(
      ChatSessionsCompanion(
        id: Value(id),
        serverId: Value(serverId),
        title: Value(title ?? '新对话'),
        createdAt: Value(now.millisecondsSinceEpoch),
        updatedAt: Value(now.millisecondsSinceEpoch),
      ),
    );
    return Session(
      id: id,
      serverId: serverId,
      title: title ?? '新对话',
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<Session?> getSessionForServer(String serverId) async {
    return getSessionById(serverId);
  }

  /// 确保每个服务器有且仅有一个对话页（sessionId = serverId）
  Future<Session> ensureServerChat({
    required String serverId,
    required String serverName,
  }) async {
    final existing = await getSessionById(serverId);
    if (existing != null) {
      final server = await _db.getServerById(serverId);
      return existing.copyWith(
        title: serverName,
        isOnline: server?.isOnline ?? false,
      );
    }
    final now = DateTime.now();
    await _db.upsertSession(
      ChatSessionsCompanion(
        id: Value(serverId),
        serverId: Value(serverId),
        title: Value(serverName),
        createdAt: Value(now.millisecondsSinceEpoch),
        updatedAt: Value(now.millisecondsSinceEpoch),
      ),
    );
    return Session(
      id: serverId,
      serverId: serverId,
      title: serverName,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<void> deleteSession(String id) async {
    await _db.deleteSession(id);
  }

  Future<void> clearUnread(String sessionId) async {
    await _db.clearUnread(sessionId);
  }

  Future<void> updateSessionMeta({
    required String sessionId,
    String? title,
    String? lastPreview,
    int? unreadDelta,
  }) async {
    final existing = await _db.getSessionById(sessionId);
    if (existing == null) {
      return;
    }
    await _db.upsertSession(
      ChatSessionsCompanion(
        id: Value(sessionId),
        serverId: Value(existing.serverId),
        title: Value(title ?? existing.title),
        createdAt: Value(existing.createdAt),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        messageCount: Value(existing.messageCount + 1),
        lastMessagePreview: Value(lastPreview ?? existing.lastMessagePreview),
        unreadCount: Value(
          unreadDelta == null ? existing.unreadCount : existing.unreadCount + unreadDelta,
        ),
      ),
    );
  }
}

/// 聊天：API 拼装 + 流式解析 + DB 写入
class ChatRepository {
  ChatRepository(
    this._db,
    this._sessionRepo,
    this._serverRepo,
  );

  final AppDatabase _db;
  final SessionRepository _sessionRepo;
  final ServerRepository _serverRepo;
  final _uuid = const Uuid();

  Future<List<Message>> loadMessages(String serverId) async {
    final rows = await _db.getMessagesBySession(serverId);
    return rows
        .map(
          (row) => Message(
            id: row.id,
            sessionId: row.sessionId,
            role: row.role,
            content: row.content,
            reasoningText: row.reasoningText,
            imageBase64s: DbMappers.decodeImages(row.imagesJson),
            createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
            tokenCount: row.tokenCount,
          ),
        )
        .toList();
  }

  Future<Message> saveUserMessage({
    required String serverId,
    required String content,
    List<String>? imageBase64s,
  }) async {
    final message = Message(
      id: _uuid.v4(),
      sessionId: serverId,
      role: 'user',
      content: content,
      imageBase64s: imageBase64s,
      createdAt: DateTime.now(),
    );
    await _db.insertMessage(
      ChatMessagesCompanion(
        id: Value(message.id),
        sessionId: Value(serverId),
        role: Value('user'),
        content: Value(content),
        imagesJson: Value(DbMappers.encodeImages(imageBase64s)),
        createdAt: Value(message.createdAt.millisecondsSinceEpoch),
      ),
    );

    final preview = content.isNotEmpty
        ? content
        : (imageBase64s != null && imageBase64s.isNotEmpty ? '[图片]' : '');
    await _sessionRepo.updateSessionMeta(
      sessionId: serverId,
      lastPreview: preview,
    );
    return message;
  }

  Future<Message> saveAssistantMessage({
    required String serverId,
    required String content,
    String? reasoningText,
  }) async {
    final message = Message(
      id: _uuid.v4(),
      sessionId: serverId,
      role: 'assistant',
      content: content,
      reasoningText: reasoningText,
      createdAt: DateTime.now(),
    );
    await _db.insertMessage(
      ChatMessagesCompanion(
        id: Value(message.id),
        sessionId: Value(serverId),
        role: Value('assistant'),
        content: Value(content),
        reasoningText: Value(reasoningText),
        createdAt: Value(message.createdAt.millisecondsSinceEpoch),
      ),
    );
    await _sessionRepo.updateSessionMeta(
      sessionId: serverId,
      lastPreview: content.length > 50 ? content.substring(0, 50) : content,
      unreadDelta: 1,
    );
    return message;
  }

  Map<String, dynamic> buildCurrentApiMessage({
    required String content,
    List<String>? imageBase64s,
  }) {
    if (imageBase64s != null && imageBase64s.isNotEmpty) {
      final parts = <Map<String, dynamic>>[];
      if (content.isNotEmpty) {
        parts.add({'type': 'text', 'text': content});
      }
      for (final image in imageBase64s) {
        final url = image.startsWith('data:')
            ? image
            : 'data:image/jpeg;base64,$image';
        parts.add({
          'type': 'image_url',
          'image_url': {'url': url},
        });
      }
      return {'role': 'user', 'content': parts};
    }
    return {'role': 'user', 'content': content};
  }

  /// F-126：API 请求只带当前一条 user 消息，不携带本地历史（上下文由服务端 session 维护）
  Stream<SseEvent> streamReply({
    required String serverId,
    required Map<String, dynamic> currentUserMessage,
    String? userInputForRuns,
  }) async* {
    final client = await _serverRepo.createApiClient(serverId);
    final apiMessages = [currentUserMessage];

    if (userInputForRuns != null && userInputForRuns.isNotEmpty) {
      try {
        final runId = await client.startRun(
          sessionKey: serverId,
          input: userInputForRuns,
          conversationHistory: const [],
          sessionId: serverId,
        );
        yield* client.streamRunEvents(runId);
        return;
      } on AgentsApiException catch (e) {
        if (e.statusCode != 404 && e.statusCode != 501 && e.statusCode != 405) {
          rethrow;
        }
      }
    }

    yield* client.streamChat(messages: apiMessages);
  }

  Future<void> submitApproval({
    required String serverId,
    required String runId,
    required String choice,
  }) async {
    final client = await _serverRepo.createApiClient(serverId);
    await client.submitApproval(runId: runId, choice: choice);
  }
}
