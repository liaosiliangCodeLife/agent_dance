import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:volume_key_board/volume_key_board.dart';

/// 音量+ 快捷审批：按一次批准，连按两次拒绝
class VolumeApprovalListener {
  VolumeApprovalListener({
    required this.onApprove,
    required this.onDeny,
    this.doublePressWindow = const Duration(milliseconds: 450),
  });

  final VoidCallback onApprove;
  final VoidCallback onDeny;
  final Duration doublePressWindow;

  int _pressCount = 0;
  Timer? _debounceTimer;
  bool _listening = false;

  void start() {
    if (_listening) {
      return;
    }
    _listening = true;
    VolumeKeyBoard.instance.addListener(_onVolumeKey);
  }

  void stop() {
    if (!_listening) {
      return;
    }
    _listening = false;
    _debounceTimer?.cancel();
    _pressCount = 0;
    VolumeKeyBoard.instance.removeListener();
  }

  void _onVolumeKey(VolumeKey event) {
    if (event != VolumeKey.up) {
      return;
    }
    _pressCount++;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(doublePressWindow, () {
      if (_pressCount >= 2) {
        onDeny();
      } else if (_pressCount == 1) {
        onApprove();
      }
      _pressCount = 0;
    });
  }

  void dispose() {
    stop();
    _debounceTimer?.cancel();
  }
}

/// 根据连按次数判断审批结果（便于单元测试）
ApprovalVolumeResult resolveVolumePressCount(int pressCount) {
  if (pressCount >= 2) {
    return ApprovalVolumeResult.deny;
  }
  if (pressCount == 1) {
    return ApprovalVolumeResult.approve;
  }
  return ApprovalVolumeResult.none;
}

enum ApprovalVolumeResult { none, approve, deny }
