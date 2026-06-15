import 'package:agent_dance/agents/models/server.dart';
import 'package:agent_dance/agents/repositories/chat_repository.dart';
import 'package:agent_dance/agents/viewmodels/server_chat_list_viewmodel.dart';
import 'package:agent_dance/services/chat_task_registry.dart';
import 'package:agent_dance/ui/common/avatar_widgets.dart';
import 'package:agent_dance/ui/chatui/chat_screen.dart';
import 'package:flutter/material.dart';

/// 智能体 Tab：服务器级对话入口（F-127）
class AgentListScreen extends StatefulWidget {
  const AgentListScreen({
    super.key,
    required this.viewModel,
    required this.chatRepository,
    required this.sessionRepository,
  });

  final ServerChatListViewModel viewModel;
  final ChatRepository chatRepository;
  final SessionRepository sessionRepository;

  @override
  State<AgentListScreen> createState() => _AgentListScreenState();
}

class _AgentListScreenState extends State<AgentListScreen> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.viewModel.addListener(_refresh);
    widget.viewModel.loadServers();
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_refresh);
    _searchController.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('聚智'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              alignment: Alignment.center,
              child: TextField(
                controller: _searchController,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
                decoration: InputDecoration(
                  hintText: '搜索',
                  hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onChanged: vm.setSearchQuery,
              ),
            ),
          ),
        ),
      ),
      body: vm.isLoading
          ? const Center(child: CircularProgressIndicator())
          : vm.filteredServers.isEmpty
              ? const Center(child: Text('暂无服务器，请先在「服务器」Tab 添加节点'))
              : ListView.builder(
                  itemCount: vm.filteredServers.length,
                  itemBuilder: (context, index) {
                    final server = vm.filteredServers[index];
                    return _ServerChatTile(
                      server: server,
                      lastPreview: vm.previewFor(server.id),
                      onTap: () => _openChat(server),
                    );
                  },
                ),
    );
  }

  Future<void> _openChat(AgentServer server) async {
    final chatVm = ChatTaskRegistry.getOrCreate(
      serverId: server.id,
      serverName: server.name,
      chatRepository: widget.chatRepository,
      sessionRepository: widget.sessionRepository,
    );
    await chatVm.init();
    if (!mounted) {
      return;
    }
    if (!server.isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${server.name} 当前离线，可查看记录，发送需联网')),
      );
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          viewModel: chatVm,
          serverName: server.name,
          serverIconKey: server.iconKey,
          isServerOnline: server.isOnline,
        ),
      ),
    );
    await widget.viewModel.loadServers();
  }
}

class _ServerChatTile extends StatelessWidget {
  const _ServerChatTile({
    required this.server,
    required this.lastPreview,
    required this.onTap,
  });

  final AgentServer server;
  final String lastPreview;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final preview = lastPreview.trim();
    final subtitle = preview.isNotEmpty
        ? preview
        : (server.isOnline
            ? '${server.host}:${server.port} · ${server.latencyMs ?? '-'}ms'
            : '${server.host}:${server.port} · 离线');

    return ListTile(
      onTap: onTap,
      leading: ServerIconAvatar(
        iconKey: server.iconKey,
        radius: 22,
        showOnlineDot: true,
        isOnline: server.isOnline,
      ),
      title: Text(server.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}
