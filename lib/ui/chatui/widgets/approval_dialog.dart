import 'dart:async';

import 'package:agent_dance/agents/models/chat_state.dart';
import 'package:agent_dance/utils/volume_approval_listener.dart';
import 'package:flutter/material.dart';

/// 危险指令审批弹窗（F-123 / F-124 / F-125）
class ApprovalDialog extends StatefulWidget {
  const ApprovalDialog({
    super.key,
    required this.request,
    required this.onChoice,
  });

  final SseApprovalRequest request;
  final ValueChanged<ApprovalChoice> onChoice;

  static const Duration autoApproveTimeout = Duration(seconds: 60);

  /// 弹出审批对话框，返回用户选择（含超时自动批准）
  static Future<ApprovalChoice> show(
    BuildContext context,
    SseApprovalRequest request,
  ) {
    return showDialog<ApprovalChoice>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ApprovalDialog(
        request: request,
        onChoice: (choice) => Navigator.of(ctx).pop(choice),
      ),
    ).then((value) => value ?? ApprovalChoice.once);
  }

  @override
  State<ApprovalDialog> createState() => _ApprovalDialogState();
}

class _ApprovalDialogState extends State<ApprovalDialog> {
  static const Duration _tick = Duration(seconds: 1);

  late int _secondsLeft;
  Timer? _countdownTimer;
  VolumeApprovalListener? _volumeListener;
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    _secondsLeft = ApprovalDialog.autoApproveTimeout.inSeconds;
    _countdownTimer = Timer.periodic(_tick, (_) {
      if (!mounted) {
        return;
      }
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        _resolve(ApprovalChoice.once);
      }
    });

    _volumeListener = VolumeApprovalListener(
      onApprove: () => _resolve(ApprovalChoice.once),
      onDeny: () => _resolve(ApprovalChoice.deny),
    )..start();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _volumeListener?.dispose();
    super.dispose();
  }

  void _resolve(ApprovalChoice choice) {
    if (_resolved) {
      return;
    }
    _resolved = true;
    _countdownTimer?.cancel();
    _volumeListener?.stop();
    widget.onChoice(choice);
  }

  List<ApprovalChoice> get _availableChoices {
    final allowed = widget.request.choices.toSet();
    return ApprovalChoice.values.where((c) => allowed.contains(c.apiValue)).toList();
  }

  String _summarize(String text, {int maxLen = 56}) {
    final normalized = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) {
      return '';
    }
    final firstLine = normalized.split(RegExp(r'[\r\n]+')).first.trim();
    if (firstLine.length <= maxLen) {
      return firstLine;
    }
    return '${firstLine.substring(0, maxLen)}…';
  }

  String get _commandSummary {
    final summary = _summarize(widget.request.command, maxLen: 72);
    return summary.isEmpty ? '(未提供命令)' : summary;
  }

  String? get _riskHint {
    final desc = _summarize(widget.request.description, maxLen: 40);
    if (desc.isEmpty) {
      return null;
    }
    final cmd = _summarize(widget.request.command, maxLen: 72);
    if (desc == cmd || cmd.contains(desc) || desc.contains(cmd)) {
      return null;
    }
    return desc;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final riskHint = _riskHint;
    return AlertDialog(
      icon: Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error, size: 32),
      title: const Text('危险操作确认'),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _commandSummary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (riskHint != null) ...[
            const SizedBox(height: 6),
            Text(
              riskHint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 14),
          LinearProgressIndicator(
            value: _secondsLeft / ApprovalDialog.autoApproveTimeout.inSeconds,
          ),
          const SizedBox(height: 6),
          Text(
            '$_secondsLeft 秒后自动批准',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
          ),
          const SizedBox(height: 4),
          Text(
            '音量+ 批准 · 连按拒绝',
            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < _availableChoices.length; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(
                  child: TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      foregroundColor: _availableChoices[i] == ApprovalChoice.deny
                          ? theme.colorScheme.error
                          : null,
                    ),
                    onPressed: () => _resolve(_availableChoices[i]),
                    child: Text(
                      _availableChoices[i].label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
