import 'package:agent_dance/agents/models/chat_state.dart';
import 'package:agent_dance/agents/models/server.dart';
import 'package:agent_dance/agents/repositories/chat_repository.dart';
import 'package:agent_dance/agents/viewmodels/app_viewmodels.dart';
import 'package:agent_dance/services/chat_task_registry.dart';
import 'package:agent_dance/ui/chatui/chat_screen.dart';
import 'package:agent_dance/ui/common/avatar_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 服务器编辑页
class ServerEditScreen extends StatefulWidget {
  const ServerEditScreen({
    super.key,
    required this.viewModel,
    required this.sessionRepository,
    required this.chatRepository,
    this.server,
  });

  final ServerListViewModel viewModel;
  final SessionRepository sessionRepository;
  final ChatRepository chatRepository;
  final AgentServer? server;

  @override
  State<ServerEditScreen> createState() => _ServerEditScreenState();
}

class _ServerEditScreenState extends State<ServerEditScreen> {
  final _nameController = TextEditingController();
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '8642');
  final _apiKeyController = TextEditingController();
  AgentType _agentType = AgentType.hermes;
  String _iconKey = ServerIconCatalog.defaultIconKey;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final server = widget.server;
    if (server != null) {
      _nameController.text = server.name;
      _hostController.text = server.host;
      _portController.text = '${server.port}';
      _agentType = server.agentType;
      _iconKey = server.iconKey;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.server == null ? '添加服务器' : '编辑服务器'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ServerIconAvatar(iconKey: _iconKey, radius: 32),
          ),
          const SizedBox(height: 8),
          ServerIconPicker(
            selectedKey: _iconKey,
            onSelected: (key) => setState(() => _iconKey = key),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: '服务器名称'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _hostController,
            decoration: const InputDecoration(
              labelText: '连接地址',
              hintText: '192.168.1.100 或 http://host:8642',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _portController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: '端口'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _apiKeyController,
            obscureText: true,
            decoration: const InputDecoration(labelText: '认证密钥'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<AgentType>(
            value: _agentType,
            decoration: const InputDecoration(labelText: '智能体类型'),
            items: AgentType.values
                .map((e) => DropdownMenuItem(value: e, child: Text(e.label)))
                .toList(),
            onChanged: (v) => setState(() => _agentType = v ?? AgentType.hermes),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _testConnection,
            child: const Text('测试连接'),
          ),
          if (vm.reachability != null)
            ListTile(
              title: Text('网络状态: ${vm.reachability!.label}'),
              subtitle: vm.testLatencyMs != null ? Text('延迟: ${vm.testLatencyMs} ms') : null,
            ),
          if (vm.testResultMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(vm.testResultMessage!),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
          if (widget.server != null) ...[
            const SizedBox(height: 24),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: _delete,
              child: const Text('删除服务器'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _testConnection() async {
    await widget.viewModel.testConnection(
      host: _hostController.text.trim(),
      port: int.tryParse(_portController.text.trim()) ?? 8642,
      apiKey: _apiKeyController.text.trim(),
    );
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final server = await widget.viewModel.saveServer(
        id: widget.server?.id,
        name: _nameController.text.trim(),
        host: _hostController.text.trim(),
        port: int.tryParse(_portController.text.trim()) ?? 8642,
        agentType: _agentType,
        apiKey: _apiKeyController.text.trim(),
        iconKey: _iconKey,
      );
      if (!mounted) {
        return;
      }
      Navigator.pop(context, server);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除服务器'),
        content: const Text('确定删除该服务器？相关会话也会被删除。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (confirm == true && widget.server != null) {
      await widget.viewModel.deleteServer(widget.server!.id);
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }
}

/// 服务器列表（Tab 2）
class ServerListScreen extends StatefulWidget {
  const ServerListScreen({
    super.key,
    required this.viewModel,
    required this.sessionRepository,
    required this.chatRepository,
  });

  final ServerListViewModel viewModel;
  final SessionRepository sessionRepository;
  final ChatRepository chatRepository;

  @override
  State<ServerListScreen> createState() => _ServerListScreenState();
}

class _ServerListScreenState extends State<ServerListScreen> {
  @override
  void initState() {
    super.initState();
    widget.viewModel.addListener(_refresh);
    widget.viewModel.loadServers();
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    return Scaffold(
      appBar: AppBar(
        title: const Text('服务器'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _openEdit(),
          ),
        ],
      ),
      body: vm.isLoading
          ? const Center(child: CircularProgressIndicator())
          : vm.servers.isEmpty
              ? const Center(child: Text('点击右上角 + 添加服务器'))
              : ListView.builder(
                  itemCount: vm.servers.length,
                  itemBuilder: (context, index) {
                    final server = vm.servers[index];
                    return ListTile(
                      leading: ServerIconAvatar(
                        iconKey: server.iconKey,
                        radius: 22,
                        showOnlineDot: true,
                        isOnline: server.isOnline,
                      ),
                      title: Text(server.name),
                      subtitle: Text(
                        '${server.host}:${server.port} · ${server.isOnline ? '${server.latencyMs ?? '-'}ms' : '离线'}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openEdit(server: server),
                      onLongPress: () => _startChat(server),
                    );
                  },
                ),
    );
  }

  Future<void> _openEdit({AgentServer? server}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ServerEditScreen(
          viewModel: widget.viewModel,
          sessionRepository: widget.sessionRepository,
          chatRepository: widget.chatRepository,
          server: server,
        ),
      ),
    );
    await widget.viewModel.loadServers();
  }

  Future<void> _startChat(AgentServer server) async {
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
  }
}
