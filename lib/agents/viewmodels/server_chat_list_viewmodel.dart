import 'package:agent_dance/agents/models/server.dart';
import 'package:agent_dance/agents/repositories/chat_repository.dart';
import 'package:agent_dance/utils/logger.dart';
import 'package:flutter/foundation.dart';

/// 智能体 Tab：按服务器维度的对话入口（F-127）
class ServerChatListViewModel extends ChangeNotifier {
  ServerChatListViewModel({
    required ServerRepository serverRepository,
    required SessionRepository sessionRepository,
  })  : _serverRepository = serverRepository,
        _sessionRepository = sessionRepository;

  final ServerRepository _serverRepository;
  final SessionRepository _sessionRepository;
  final _log = Logger('ServerChatListViewModel');

  List<AgentServer> servers = [];
  final Map<String, String> lastMessagePreviews = {};
  String searchQuery = '';
  bool isLoading = false;

  List<AgentServer> get filteredServers {
    if (searchQuery.isEmpty) {
      return servers;
    }
    final q = searchQuery.toLowerCase();
    return servers.where((s) => s.name.toLowerCase().contains(q)).toList();
  }

  String previewFor(String serverId) => lastMessagePreviews[serverId] ?? '';

  Future<void> loadServers() async {
    isLoading = true;
    notifyListeners();
    try {
      await _serverRepository.refreshAllServerStatus();
      servers = await _serverRepository.getAllServers();
      final sessions = await _sessionRepository.getAllSessions();
      lastMessagePreviews.clear();
      for (final session in sessions) {
        if (!lastMessagePreviews.containsKey(session.serverId)) {
          lastMessagePreviews[session.serverId] = session.lastMessagePreview;
        }
      }
    } catch (e, st) {
      _log.error('加载服务器对话入口失败', e, st);
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void setSearchQuery(String value) {
    searchQuery = value;
    notifyListeners();
  }
}
