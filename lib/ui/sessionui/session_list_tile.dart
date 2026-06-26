import 'package:agent_dance/agents/models/session.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// 会话列表项（F-131）
class SessionListTile extends StatelessWidget {
  const SessionListTile({
    super.key,
    required this.session,
    required this.onTap,
    required this.onDelete,
    required this.onRename,
  });

  final Session session;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onRename;

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final sessionDay = DateTime(time.year, time.month, time.day);
    if (sessionDay == today) {
      return DateFormat('HH:mm').format(time);
    }
    if (sessionDay == today.subtract(const Duration(days: 1))) {
      return '昨天';
    }
    return DateFormat('MM-dd').format(time);
  }

  @override
  Widget build(BuildContext context) {
    final preview = session.lastMessagePreview.trim();
    final subtitle = preview.isNotEmpty ? preview : '暂无消息';

    return Dismissible(
      key: ValueKey(session.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Theme.of(context).colorScheme.error,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        return showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('删除会话'),
            content: Text('确定删除「${session.title}」？聊天记录将一并清除。'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
            ],
          ),
        );
      },
      onDismissed: (_) => onDelete(),
      child: ListTile(
        onTap: onTap,
        onLongPress: onRename,
        title: Text(session.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Text(
          _formatTime(session.updatedAt),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ),
    );
  }
}
