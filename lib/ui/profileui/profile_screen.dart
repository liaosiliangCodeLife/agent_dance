import 'package:agent_dance/agents/viewmodels/app_viewmodels.dart';
import 'package:agent_dance/config/app_config.dart';
import 'package:agent_dance/ui/chatui/widgets/chat_widgets.dart';
import 'package:agent_dance/ui/common/avatar_widgets.dart';
import 'package:agent_dance/utils/logger.dart';
import 'package:agent_dance/utils/media_services.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:local_auth/local_auth.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 个人页（Tab 4）
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.viewModel,
    required this.onThemeChanged,
  });

  final ProfileViewModel viewModel;
  final ValueChanged<ThemeMode> onThemeChanged;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _auth = LocalAuthentication();
  final _imageService = ImageService();

  @override
  void initState() {
    super.initState();
    widget.viewModel.addListener(_refresh);
    widget.viewModel.load();
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
      appBar: AppBar(title: const Text('我')),
      body: ListView(
        children: [
          ListTile(
            leading: GestureDetector(
              onTap: _pickAvatar,
              child: UserAvatar(
                avatarPath: vm.avatarPath,
                nickname: vm.nickname,
                radius: 24,
              ),
            ),
            title: Text(vm.nickname),
            subtitle: Text('设备 ID: ${vm.deviceId.substring(0, 8)}...'),
            trailing: IconButton(
              icon: const Icon(Icons.edit),
              onPressed: _editNickname,
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.palette),
            title: const Text('主题切换'),
            subtitle: Text(_themeLabel(AppConfig.themeMode)),
            onTap: _pickTheme,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.notifications),
            title: const Text('消息通知'),
            subtitle: const Text('预留功能'),
            value: false,
            onChanged: null,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.fingerprint),
            title: const Text('生物识别锁定'),
            value: vm.biometricEnabled,
            onChanged: (v) async {
              if (v) {
                final ok = await _auth.authenticate(
                  localizedReason: '启用 App 锁定',
                );
                if (ok) {
                  await vm.setBiometricEnabled(true);
                }
              } else {
                await vm.setBiometricEnabled(false);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.storage),
            title: const Text('数据管理'),
            onTap: _showDataManagement,
          ),
          ListTile(
            leading: const Icon(Icons.article),
            title: const Text('日志查看'),
            onTap: _showLogs,
          ),
          ListTile(
            leading: const Icon(Icons.info),
            title: const Text('关于'),
            onTap: _showAbout,
          ),
        ],
      ),
    );
  }

  Future<void> _editNickname() async {
    final controller = TextEditingController(text: widget.viewModel.nickname);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑昵称'),
        content: TextField(controller: controller),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('保存')),
        ],
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      await widget.viewModel.updateNickname(result.trim());
    }
  }

  Future<void> _pickAvatar() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => ImagePickerSheet(
        onCamera: () => _saveAvatar(ImageSource.camera),
        onGallery: () => _saveAvatar(ImageSource.gallery),
      ),
    );
  }

  Future<void> _saveAvatar(ImageSource source) async {
    final path = await _imageService.pickAndSaveAvatar(source: source);
    if (path != null) {
      await widget.viewModel.updateAvatar(path);
    }
  }

  String _themeLabel(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.light => '亮色',
      ThemeMode.dark => '暗色',
      ThemeMode.system => '跟随系统',
    };
  }

  Future<void> _pickTheme() async {
    final current = AppConfig.themeMode;
    final selected = await showDialog<ThemeMode>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择主题'),
        children: [
          RadioListTile<ThemeMode>(
            title: const Text('跟随系统'),
            value: ThemeMode.system,
            groupValue: current,
            onChanged: (v) => Navigator.pop(ctx, v),
          ),
          RadioListTile<ThemeMode>(
            title: const Text('亮色'),
            value: ThemeMode.light,
            groupValue: current,
            onChanged: (v) => Navigator.pop(ctx, v),
          ),
          RadioListTile<ThemeMode>(
            title: const Text('暗色'),
            value: ThemeMode.dark,
            groupValue: current,
            onChanged: (v) => Navigator.pop(ctx, v),
          ),
        ],
      ),
    );
    if (selected != null) {
      await AppConfig.setThemeMode(selected);
      widget.onThemeChanged(selected);
      setState(() {});
    }
  }

  Future<void> _showDataManagement() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.cleaning_services),
              title: const Text('清除缓存'),
              onTap: () async {
                await widget.viewModel.clearCache();
                if (ctx.mounted) Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('缓存已清除')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever),
              title: const Text('清空所有数据'),
              onTap: () async {
                await widget.viewModel.clearAllData();
                if (ctx.mounted) Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('所有数据已清空')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showLogs() async {
    final logs = Logger.getRecentLogs();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _LogViewerScreen(logs: logs),
      ),
    );
  }

  Future<void> _showAbout() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    showAboutDialog(
      context: context,
      applicationName: '聚智',
      applicationVersion: info.version,
      applicationLegalese: '© Brtc',
    );
  }
}

class _LogViewerScreen extends StatefulWidget {
  const _LogViewerScreen({required this.logs});

  final List<String> logs;

  @override
  State<_LogViewerScreen> createState() => _LogViewerScreenState();
}

class _LogViewerScreenState extends State<_LogViewerScreen> {
  LogLevel? _filter;

  @override
  Widget build(BuildContext context) {
    final logs = _filter == null
        ? widget.logs
        : widget.logs.where((l) => l.contains('[${_filter!.name.toUpperCase()}]')).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('日志'),
        actions: [
          PopupMenuButton<LogLevel?>(
            onSelected: (v) => setState(() => _filter = v),
            itemBuilder: (_) => [
              const PopupMenuItem(value: null, child: Text('全部')),
              ...LogLevel.values.map(
                (e) => PopupMenuItem(value: e, child: Text(e.name)),
              ),
            ],
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: logs.length,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Text(logs[i], style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
        ),
      ),
    );
  }
}
