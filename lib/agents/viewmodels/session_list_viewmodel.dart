import 'package:agent_dance/agents/models/session.dart';
import 'package:agent_dance/agents/repositories/chat_repository.dart';
import 'package:agent_dance/services/chat_task_registry.dart';
import 'package:agent_dance/utils/logger.dart';
import 'package:flutter/foundation.dart';

/// 会话列表 ViewModel（F-131 ~ F-135）
class SessionListViewModel extends ChangeNotifier {
  SessionListViewModel({
    required SessionRepository sessionRepository,
    required this.serverId,
    required this.serverName,
  }) : _sessionRepository = sessionRepository;

  final SessionRepository _sessionRepository;
  final String serverId;
  final String serverName;
  final _log = Logger('SessionListViewModel');

  List<Session> sessions = [];
  bool isLoading = false;

  Future<void> loadSessions() async {
    isLoading = true;
    notifyListeners();
    try {
      sessions = await _sessionRepository.getSessionsByServer(serverId);
    } catch (e, st) {
      _log.error('加载会话列表失败', e, st);
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<Session> createSession() async {
    final session = await _sessionRepository.createSession(serverId: serverId);
    await loadSessions();
    return session;
  }

  Future<void> deleteSession(String sessionId) async {
    ChatTaskRegistry.remove(sessionId);
    await _sessionRepository.deleteSession(sessionId);
    await loadSessions();
  }

  Future<void> renameSession(String sessionId, String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      return;
    }
    await _sessionRepository.updateSessionTitle(sessionId, trimmed);
    await loadSessions();
  }
}
