import 'package:agent_dance/agents/models/server.dart';
import 'package:agent_dance/agents/repositories/chat_repository.dart';
import 'package:agent_dance/agents/viewmodels/session_list_viewmodel.dart';
import 'package:agent_dance/services/chat_task_registry.dart';
import 'package:agent_dance/ui/chatui/chat_screen.dart';
import 'package:agent_dance/ui/common/avatar_widgets.dart';
import 'package:agent_dance/ui/sessionui/session_list_tile.dart';
import 'package:flutter/material.dart';

/// 会话列表页（F-131 ~ F-136）
class SessionListScreen extends StatefulWidget {
  const SessionListScreen({
    super.key,
    required this.server,
    required this.sessionRepository,
    required this.chatRepository,
  });

  final AgentServer server;
  final SessionRepository sessionRepository;
  final ChatRepository chatRepository;

  @override
  State<SessionListScreen> createState() => _SessionListScreenState();
}

class _SessionListScreenState extends State<SessionListScreen> {
  late final SessionListViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = SessionListViewModel(
      sessionRepository: widget.sessionRepository,
      serverId: widget.server.id,
      serverName: widget.server.name,
    );
    _viewModel.addListener(_refresh);
    _viewModel.loadSessions();
  }

  @override
  void dispose() {
    _viewModel.removeListener(_refresh);
    _viewModel.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final vm = _viewModel;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ServerIconAvatar(iconKey: widget.server.iconKey, radius: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Text(widget.server.name, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新建会话',
            onPressed: _createAndOpenSession,
          ),
        ],
      ),
      body: vm.isLoading
          ? const Center(child: CircularProgressIndicator())
          : vm.sessions.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('暂无会话'),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _createAndOpenSession,
                        icon: const Icon(Icons.add),
                        label: const Text('新建对话'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: vm.sessions.length,
                  itemBuilder: (context, index) {
                    final session = vm.sessions[index];
                    return SessionListTile(
                      session: session,
                      onTap: () => _openChat(session.id, session.title),
                      onDelete: () => vm.deleteSession(session.id),
                      onRename: () => _renameSession(session.id, session.title),
                    );
                  },
                ),
    );
  }

  Future<void> _createAndOpenSession() async {
    final session = await _viewModel.createSession();
    if (!mounted) {
      return;
    }
    await _openChat(session.id, session.title);
  }

  Future<void> _openChat(String sessionId, String sessionTitle) async {
    final chatVm = ChatTaskRegistry.getOrCreate(
      sessionId: sessionId,
      serverId: widget.server.id,
      serverName: widget.server.name,
      sessionTitle: sessionTitle,
      chatRepository: widget.chatRepository,
      sessionRepository: widget.sessionRepository,
    );
    await chatVm.init();
    if (!mounted) {
      return;
    }
    if (!widget.server.isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.server.name} 当前离线，可查看记录，发送需联网')),
      );
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          viewModel: chatVm,
          serverId: widget.server.id,
          serverName: widget.server.name,
          sessionTitle: sessionTitle,
          serverIconKey: widget.server.iconKey,
          isServerOnline: widget.server.isOnline,
          sessionRepository: widget.sessionRepository,
          chatRepository: widget.chatRepository,
        ),
      ),
    );
    await _viewModel.loadSessions();
  }

  Future<void> _renameSession(String sessionId, String currentTitle) async {
    final controller = TextEditingController(text: currentTitle);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改会话标题'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入新标题'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newTitle != null && newTitle.isNotEmpty) {
      await _viewModel.renameSession(sessionId, newTitle);
    }
  }
}
