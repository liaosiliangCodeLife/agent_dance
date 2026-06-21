import 'dart:io';

import 'package:agent_dance/config/app_config.dart';
import 'package:flutter/material.dart';

/// 服务器图标预设库（F-215）
class ServerIconCatalog {
  ServerIconCatalog._();

  static const defaultIconKey = 'emoji:🤖';

  /// 预设 emoji 图标
  static const List<String> emojiIcons = [
    '🤖',
    '💻',
    '🖥️',
    '🏠',
    '☁️',
    '🧠',
    '⚡',
    '🔮',
    '🎯',
    '🚀',
    '🛠️',
    '📡',
    '🌐',
    '🦾',
    '🎮',
    '📚',
  ];

  /// 内置 Material 图标（key 不含前缀）
  static const Map<String, IconData> materialIcons = {
    'dns': Icons.dns,
    'smart_toy': Icons.smart_toy,
    'computer': Icons.computer,
    'cloud': Icons.cloud,
    'home': Icons.home,
    'hub': Icons.hub,
    'memory': Icons.memory,
    'psychology': Icons.psychology,
    'rocket_launch': Icons.rocket_launch,
    'settings': Icons.settings,
    'terminal': Icons.terminal,
    'wifi': Icons.wifi,
    'code': Icons.code,
    'developer_board': Icons.developer_board,
    'storage': Icons.storage,
    'workspaces': Icons.workspaces,
  };

  static String emojiKey(String emoji) => 'emoji:$emoji';

  static String iconKey(String name) => 'icon:$name';

  static bool isEmojiKey(String key) => key.startsWith('emoji:');

  static bool isIconKey(String key) => key.startsWith('icon:');

  static String? emojiFromKey(String key) {
    if (!isEmojiKey(key)) {
      return null;
    }
    return key.substring('emoji:'.length);
  }

  static IconData? iconDataFromKey(String key) {
    if (!isIconKey(key)) {
      return null;
    }
    return materialIcons[key.substring('icon:'.length)];
  }

  static IconData iconDataOrDefault(String key) {
    return iconDataFromKey(key) ?? Icons.dns;
  }
}

/// 服务器图标头像（emoji 或 Material 图标）
class ServerIconAvatar extends StatelessWidget {
  const ServerIconAvatar({
    super.key,
    required this.iconKey,
    this.radius = 20,
    this.showOnlineDot = false,
    this.isOnline = false,
  });

  final String iconKey;
  final double radius;
  final bool showOnlineDot;
  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    final emoji = ServerIconCatalog.emojiFromKey(iconKey);
    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
      child: emoji != null
          ? Text(emoji, style: TextStyle(fontSize: radius * 0.9))
          : Icon(
              ServerIconCatalog.iconDataOrDefault(iconKey),
              size: radius,
              color: Theme.of(context).colorScheme.onSecondaryContainer,
            ),
    );

    if (!showOnlineDot) {
      return avatar;
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: radius * 0.55,
            height: radius * 0.55,
            decoration: BoxDecoration(
              color: isOnline ? Colors.green : Colors.grey,
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).colorScheme.surface,
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 用户头像（本地图片或昵称首字，F-128 / F-401）
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    this.avatarPath,
    this.nickname,
    this.radius = 18,
  });

  final String? avatarPath;
  final String? nickname;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final initial = (nickname != null && nickname!.isNotEmpty)
        ? nickname!.characters.first.toUpperCase()
        : 'U';

    final path = avatarPath;
    if (path != null && path.isNotEmpty && File(path).existsSync()) {
      // 同路径覆盖写入时需 revision 打破 FileImage 缓存
      final revision = AppConfig.userProfile.revision;
      return CircleAvatar(
        radius: radius,
        key: ValueKey('user-avatar-$path-$revision'),
        backgroundImage: FileImage(File(path)),
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      child: Text(
        initial,
        style: TextStyle(
          fontSize: radius * 0.75,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

/// 服务器图标选择器
class ServerIconPicker extends StatelessWidget {
  const ServerIconPicker({
    super.key,
    required this.selectedKey,
    required this.onSelected,
  });

  final String selectedKey;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('选择图标', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final emoji in ServerIconCatalog.emojiIcons)
              _PickerTile(
                selected: selectedKey == ServerIconCatalog.emojiKey(emoji),
                onTap: () => onSelected(ServerIconCatalog.emojiKey(emoji)),
                child: Text(emoji, style: const TextStyle(fontSize: 24)),
              ),
            for (final entry in ServerIconCatalog.materialIcons.entries)
              _PickerTile(
                selected: selectedKey == ServerIconCatalog.iconKey(entry.key),
                onTap: () => onSelected(ServerIconCatalog.iconKey(entry.key)),
                child: Icon(entry.value),
              ),
          ],
        ),
      ],
    );
  }
}

class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
          color: selected
              ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4)
              : null,
        ),
        child: child,
      ),
    );
  }
}
