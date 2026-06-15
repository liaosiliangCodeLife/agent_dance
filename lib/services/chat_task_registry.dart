import 'package:agent_dance/agents/repositories/chat_repository.dart';
import 'package:agent_dance/agents/viewmodels/chat_viewmodel.dart';

/// 后台运行中的聊天任务注册表（F-505），按服务器维度（F-127）
class ChatTaskRegistry {
  ChatTaskRegistry._();

  static final Map<String, _RegistryEntry> _entries = <String, _RegistryEntry>{};

  static ChatViewModel getOrCreate({
    required String serverId,
    required String serverName,
    required ChatRepository chatRepository,
    required SessionRepository sessionRepository,
  }) {
    final existing = _entries[serverId];
    if (existing != null) {
      return existing.viewModel;
    }
    final vm = ChatViewModel(
      serverId: serverId,
      serverName: serverName,
      chatRepository: chatRepository,
      sessionRepository: sessionRepository,
    );
    _entries[serverId] = _RegistryEntry(viewModel: vm, serverName: serverName);
    return vm;
  }

  static String? serverNameFor(String serverId) {
    return _entries[serverId]?.serverName;
  }

  static ChatViewModel? find(String serverId) {
    return _entries[serverId]?.viewModel;
  }

  static void onScreenClosed(String serverId) {
    final entry = _entries[serverId];
    if (entry == null) {
      return;
    }
    entry.viewModel.detachUi();
  }

  static void onTaskFinished(String serverId) {
    final entry = _entries[serverId];
    if (entry == null) {
      return;
    }
    if (!entry.viewModel.uiAttached) {
      entry.viewModel.disposeInternal();
      _entries.remove(serverId);
    }
  }

  static void remove(String serverId) {
    final entry = _entries.remove(serverId);
    entry?.viewModel.disposeInternal();
  }
}

class _RegistryEntry {
  _RegistryEntry({required this.viewModel, required this.serverName});

  final ChatViewModel viewModel;
  final String serverName;
}
