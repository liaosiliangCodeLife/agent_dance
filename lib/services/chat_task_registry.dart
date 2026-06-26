import 'package:agent_dance/agents/repositories/chat_repository.dart';
import 'package:agent_dance/agents/viewmodels/chat_viewmodel.dart';

/// 后台运行中的聊天任务注册表（F-505），按会话维度
class ChatTaskRegistry {
  ChatTaskRegistry._();

  static final Map<String, _RegistryEntry> _entries = <String, _RegistryEntry>{};

  static ChatViewModel getOrCreate({
    required String sessionId,
    required String serverId,
    required String serverName,
    required String sessionTitle,
    required ChatRepository chatRepository,
    required SessionRepository sessionRepository,
  }) {
    final existing = _entries[sessionId];
    if (existing != null) {
      existing.viewModel.sessionTitle = sessionTitle;
      return existing.viewModel;
    }
    final vm = ChatViewModel(
      sessionId: sessionId,
      serverId: serverId,
      serverName: serverName,
      sessionTitle: sessionTitle,
      chatRepository: chatRepository,
      sessionRepository: sessionRepository,
    );
    _entries[sessionId] = _RegistryEntry(
      viewModel: vm,
      serverName: serverName,
      sessionTitle: sessionTitle,
    );
    return vm;
  }

  static String? serverNameFor(String sessionId) {
    return _entries[sessionId]?.serverName;
  }

  static ChatViewModel? find(String sessionId) {
    return _entries[sessionId]?.viewModel;
  }

  static void onScreenClosed(String sessionId) {
    final entry = _entries[sessionId];
    if (entry == null) {
      return;
    }
    entry.viewModel.detachUi();
  }

  static void onTaskFinished(String sessionId) {
    final entry = _entries[sessionId];
    if (entry == null) {
      return;
    }
    if (!entry.viewModel.uiAttached) {
      entry.viewModel.disposeInternal();
      _entries.remove(sessionId);
    }
  }

  static void remove(String sessionId) {
    final entry = _entries.remove(sessionId);
    entry?.viewModel.disposeInternal();
  }
}

class _RegistryEntry {
  _RegistryEntry({
    required this.viewModel,
    required this.serverName,
    required this.sessionTitle,
  });

  final ChatViewModel viewModel;
  final String serverName;
  final String sessionTitle;
}
