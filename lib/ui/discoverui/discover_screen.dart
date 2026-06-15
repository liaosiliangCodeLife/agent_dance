import 'package:agent_dance/agents/models/server.dart';
import 'package:agent_dance/agents/viewmodels/app_viewmodels.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 发现 AI（Tab 3）
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key, required this.viewModel});

  final DiscoverViewModel viewModel;

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  @override
  void initState() {
    super.initState();
    widget.viewModel.addListener(_refresh);
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
      appBar: AppBar(title: const Text('发现 AI')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.store),
            title: const Text('AI 应用市场'),
            subtitle: const Text('即将上线'),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.wifi_find),
            title: const Text('附近智能体'),
            subtitle: Text(vm.isScanning ? '扫描中...' : '局域网自动发现'),
            trailing: vm.isScanning ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : null,
            onTap: () async {
              await vm.scanNearbyAgents();
              if (!mounted) return;
              await _showNearbyAgents(vm.discoveredAgents);
            },
          ),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('使用帮助'),
            onTap: () => _showHelp(context),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('关于'),
            onTap: () => _showAbout(context),
          ),
        ],
      ),
    );
  }

  Future<void> _showNearbyAgents(List<DiscoveredAgent> agents) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        if (agents.isEmpty) {
          return const SafeArea(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('未发现附近智能体节点'),
            ),
          );
        }
        return SafeArea(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: agents.length,
            itemBuilder: (context, index) {
              final agent = agents[index];
              return ListTile(
                title: Text(agent.name),
                subtitle: Text('${agent.host}:${agent.port}'),
                trailing: TextButton(
                  child: const Text('添加'),
                  onPressed: () async {
                    await widget.viewModel.addDiscoveredAgent(agent);
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已添加到服务器列表')),
                      );
                    }
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _showHelp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('使用帮助'),
        content: const Text(
          '1. 在「服务器」Tab 添加 Agents 节点\n'
          '2. 长按服务器可快速发起对话\n'
          '3. 支持文字、图片、语音多模态消息\n'
          '4. 思考过程可在消息中展开查看',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('知道了')),
        ],
      ),
    );
  }

  Future<void> _showAbout(BuildContext context) async {
    final info = await PackageInfo.fromPlatform();
    if (!context.mounted) return;
    showAboutDialog(
      context: context,
      applicationName: '聚智',
      applicationVersion: info.version,
      applicationLegalese: '© Brtc · 开源 MIT',
      children: const [
        Text('对接 Agents Agent 的 AI 助手移动端 App'),
      ],
    );
  }
}
