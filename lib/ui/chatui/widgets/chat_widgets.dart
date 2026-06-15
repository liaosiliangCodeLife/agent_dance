import 'dart:convert';
import 'dart:typed_data';

import 'package:agent_dance/agents/models/message.dart';
import 'package:agent_dance/ui/common/avatar_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

/// 思考过程折叠区
class ThinkingSection extends StatefulWidget {
  const ThinkingSection({
    super.key,
    required this.reasoningText,
    this.isStreaming = false,
  });

  final String reasoningText;
  final bool isStreaming;

  @override
  State<ThinkingSection> createState() => _ThinkingSectionState();
}

class _ThinkingSectionState extends State<ThinkingSection> {
  @override
  Widget build(BuildContext context) {
    if (widget.reasoningText.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: Theme.of(context).colorScheme.outline, width: 3),
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: widget.isStreaming,
          onExpansionChanged: (_) {},
          tilePadding: const EdgeInsets.symmetric(horizontal: 8),
          title: Text(
            widget.isStreaming ? '💭 思考中...' : '💭 思考过程',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 8, 8),
              child: Text(
                widget.reasoningText,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 流式文本 + 闪烁光标
class StreamingText extends StatefulWidget {
  const StreamingText({super.key, required this.text});

  final String text;

  @override
  State<StreamingText> createState() => _StreamingTextState();
}

class _StreamingTextState extends State<StreamingText> {
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _blink();
  }

  Future<void> _blink() async {
    while (mounted) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        setState(() => _visible = !_visible);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: widget.text,
            style: const TextStyle(fontSize: 15, height: 1.4),
          ),
          TextSpan(
            text: _visible ? '▌' : ' ',
            style: TextStyle(
              fontSize: 15,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 消息气泡
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.userAvatarPath,
    this.userNickname,
  });

  final Message message;
  final String? userAvatarPath;
  final String? userNickname;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final bg = isUser
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.surfaceContainerHighest;

    final bubble = Container(
      width: isUser ? null : double.infinity,
      constraints: isUser
          ? BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.72)
          : const BoxConstraints(),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: isUser
            ? BorderRadius.circular(16)
            : const BorderRadius.vertical(top: Radius.circular(4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message.hasReasoning)
            ThinkingSection(reasoningText: message.reasoningText!),
          if (message.isAssistant)
            MarkdownBody(
              data: message.content,
              styleSheet: MarkdownStyleSheet(p: TextStyle(fontSize: 15)),
              onTapLink: (text, href, title) {
                if (href != null) {
                  launchUrl(Uri.parse(href));
                }
              },
            )
          else
            Text(message.content),
          if (message.hasImages) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: message.imageBase64s!.map((img) {
                final bytes = base64Decode(
                  img.contains(',') ? img.split(',').last : img,
                );
                return GestureDetector(
                  onTap: () => _showImagePreview(context, bytes),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(bytes, width: 120, height: 120, fit: BoxFit.cover),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );

    if (isUser) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            bubble,
            const SizedBox(width: 8),
            UserAvatar(
              avatarPath: userAvatarPath,
              nickname: userNickname,
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: bubble,
    );
  }

  void _showImagePreview(BuildContext context, List<int> bytes) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: InteractiveViewer(
          child: Image.memory(Uint8List.fromList(bytes)),
        ),
      ),
    );
  }
}

/// 工具进度条
class ToolProgressBar extends StatelessWidget {
  const ToolProgressBar({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 6),
          Text(message, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// 微信风格附件面板（相册 / 拍照）
class ChatAttachmentPanel extends StatelessWidget {
  const ChatAttachmentPanel({
    super.key,
    required this.onCamera,
    required this.onGallery,
  });

  final VoidCallback onCamera;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            _AttachmentItem(
              icon: Icons.photo_library_outlined,
              label: '相册',
              color: theme.colorScheme.primaryContainer,
              onTap: () {
                Navigator.pop(context);
                onGallery();
              },
            ),
            const SizedBox(width: 28),
            _AttachmentItem(
              icon: Icons.camera_alt_outlined,
              label: '拍照',
              color: theme.colorScheme.secondaryContainer,
              onTap: () {
                Navigator.pop(context);
                onCamera();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentItem extends StatelessWidget {
  const _AttachmentItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 28),
          ),
          const SizedBox(height: 8),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// 图片选择 BottomSheet（兼容旧调用）
class ImagePickerSheet extends StatelessWidget {
  const ImagePickerSheet({
    super.key,
    required this.onCamera,
    required this.onGallery,
  });

  final VoidCallback onCamera;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.camera_alt),
            title: const Text('拍照'),
            onTap: () {
              Navigator.pop(context);
              onCamera();
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('从相册选择'),
            onTap: () {
              Navigator.pop(context);
              onGallery();
            },
          ),
          ListTile(
            leading: const Icon(Icons.close),
            title: const Text('取消'),
            onTap: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}
