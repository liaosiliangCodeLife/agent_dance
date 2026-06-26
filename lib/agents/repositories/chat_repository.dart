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

  Future<List<Session>> getSessionsByServer(String serverId) async {
    final rows = await _db.getSessionsByServer(serverId);
    final server = await _db.getServerById(serverId);
    final isOnline = server?.isOnline ?? false;
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
            isOnline: isOnline,
          ),
        )
        .toList();
  }

  static String defaultSessionTitle() {
    final now = DateTime.now();
    final date =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return '新对话 $date';
  }

  Future<Session> createSession({required String serverId, String? title}) async {
    final now = DateTime.now();
    final id = _uuid.v4();
    final sessionTitle = title ?? defaultSessionTitle();
    await _db.upsertSession(
      ChatSessionsCompanion(
        id: Value(id),
        serverId: Value(serverId),
        title: Value(sessionTitle),
        createdAt: Value(now.millisecondsSinceEpoch),
        updatedAt: Value(now.millisecondsSinceEpoch),
      ),
    );
    return Session(
      id: id,
      serverId: serverId,
      title: sessionTitle,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<void> updateSessionTitle(String sessionId, String title) async {
    final existing = await _db.getSessionById(sessionId);
    if (existing == null) {
      return;
    }
    await _db.upsertSession(
      ChatSessionsCompanion(
        id: Value(sessionId),
        serverId: Value(existing.serverId),
        title: Value(title),
        createdAt: Value(existing.createdAt),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        messageCount: Value(existing.messageCount),
        lastMessagePreview: Value(existing.lastMessagePreview),
        unreadCount: Value(existing.unreadCount),
      ),
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
  final _log = Logger('ChatRepository');

  Future<List<Message>> loadMessages(String sessionId) async {
    final rows = await _db.getMessagesBySession(sessionId);
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
    required String sessionId,
    required String content,
    List<String>? imageBase64s,
  }) async {
    final message = Message(
      id: _uuid.v4(),
      sessionId: sessionId,
      role: 'user',
      content: content,
      imageBase64s: imageBase64s,
      createdAt: DateTime.now(),
    );
    await _db.insertMessage(
      ChatMessagesCompanion(
        id: Value(message.id),
        sessionId: Value(sessionId),
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
      sessionId: sessionId,
      lastPreview: preview,
    );
    return message;
  }

  Future<Message> saveAssistantMessage({
    required String sessionId,
    required String content,
    String? reasoningText,
  }) async {
    final message = Message(
      id: _uuid.v4(),
      sessionId: sessionId,
      role: 'assistant',
      content: content,
      reasoningText: reasoningText,
      createdAt: DateTime.now(),
    );
    await _db.insertMessage(
      ChatMessagesCompanion(
        id: Value(message.id),
        sessionId: Value(sessionId),
        role: Value('assistant'),
        content: Value(content),
        reasoningText: Value(reasoningText),
        createdAt: Value(message.createdAt.millisecondsSinceEpoch),
      ),
    );
    await _sessionRepo.updateSessionMeta(
      sessionId: sessionId,
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

  /// API 请求携带 sessionId + 对话历史；Runs 失败时降级 chat/completions 也带历史
  Stream<SseEvent> streamReply({
    required String serverId,
    required String sessionId,
    required Map<String, dynamic> currentUserMessage,
    String? userInputForRuns,
    List<Map<String, dynamic>> conversationHistory = const [],
  }) async* {
    final client = await _serverRepo.createApiClient(serverId);
    final sessionKey = 'agent_dance:$serverId';
    _log.info('streamReply', {
      'sessionId': sessionId,
      'sessionKey': sessionKey,
      'historyLen': conversationHistory.length,
      'useRuns': userInputForRuns != null && userInputForRuns.isNotEmpty,
    });

    if (userInputForRuns != null && userInputForRuns.isNotEmpty) {
      var runsYielded = false;
      try {
        final runId = await client.startRun(
          sessionKey: sessionKey,
          input: userInputForRuns,
          conversationHistory: conversationHistory,
          sessionId: sessionId,
        );
        await for (final event in client.streamRunEvents(runId)) {
          runsYielded = true;
          yield event;
        }
        return;
      } on AgentsApiException catch (e) {
        if (runsYielded) {
          return;
        }
        if (e.statusCode != 404 && e.statusCode != 501 && e.statusCode != 405) {
          rethrow;
        }
        _log.info('Runs API 不可用，降级 Chat Completions', {'sessionId': sessionId});
      }
    }

    final allMessages = [...conversationHistory, currentUserMessage];
    yield* client.streamChat(
      messages: allMessages,
      sessionId: sessionId,
      sessionKey: sessionKey,
    );
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
