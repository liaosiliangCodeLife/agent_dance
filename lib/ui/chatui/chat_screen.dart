import 'dart:async';

import 'package:agent_dance/agents/models/chat_state.dart';
import 'package:agent_dance/agents/viewmodels/chat_viewmodel.dart';
import 'package:agent_dance/config/app_config.dart';
import 'package:agent_dance/services/app_services.dart';
import 'package:agent_dance/services/chat_task_registry.dart';
import 'package:agent_dance/ui/chatui/widgets/approval_dialog.dart';
import 'package:agent_dance/ui/chatui/widgets/chat_widgets.dart';
import 'package:agent_dance/ui/common/avatar_widgets.dart';
import 'package:agent_dance/utils/media_services.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// 聊天主页面
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.viewModel,
    required this.serverName,
    this.serverIconKey,
    this.isServerOnline = true,
  });

  final ChatViewModel viewModel;
  final String serverName;
  final String? serverIconKey;
  final bool isServerOnline;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _scrollController = ScrollController();
  final _inputFocusNode = FocusNode();
  final _imageService = ImageService();
  bool _hasText = false;
  bool _showingApproval = false;
  String _serverIconKey = ServerIconCatalog.defaultIconKey;
  final _textController = TextEditingController();
  double _keyboardInset = 0;

  @override
  void initState() {
    super.initState();
    _serverIconKey = widget.serverIconKey ?? ServerIconCatalog.defaultIconKey;
    _textController.addListener(_onTextChanged);
    _inputFocusNode.addListener(_onInputFocusChanged);
    widget.viewModel.attachUi();
    widget.viewModel.addListener(_onVmChanged);
    unawaited(_initChat());
    _loadServerIconIfNeeded();
  }

  void _onInputFocusChanged() {
    if (_inputFocusNode.hasFocus) {
      _scrollToBottomAfterKeyboard();
    }
  }

  /// 等键盘动画完成后再滚到底部，避免消息被输入法遮挡
  void _scrollToBottomAfterKeyboard() {
    Future<void>.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _scrollToBottom(animated: true);
      }
    });
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _scrollToBottom(animated: true);
      }
    });
  }

  Future<void> _initChat() async {
    await widget.viewModel.init();
    if (mounted) {
      _scrollToBottom(animated: false);
    }
  }

  Future<void> _loadServerIconIfNeeded() async {
    if (widget.serverIconKey != null) {
      return;
    }
    final server = await AppServices.instance.serverRepository
        .getServerById(widget.viewModel.serverId);
    if (server != null && mounted) {
      setState(() => _serverIconKey = server.iconKey);
    }
  }

  void _onTextChanged() {
    final hasText = _textController.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_onVmChanged);
    _textController.removeListener(_onTextChanged);
    _inputFocusNode.removeListener(_onInputFocusChanged);
    _inputFocusNode.dispose();
    _textController.dispose();
    ChatTaskRegistry.onScreenClosed(widget.viewModel.serverId);
    _scrollController.dispose();
    super.dispose();
  }

  void _onVmChanged() {
    if (widget.viewModel.errorMessage != null) {
      final msg = widget.viewModel.errorMessage!;
      widget.viewModel.errorMessage = null;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
    if (widget.viewModel.shouldShowApprovalDialog && !_showingApproval) {
      _showingApproval = true;
      widget.viewModel.markApprovalDialogVisible();
      unawaited(_showApprovalDialog());
    }
    setState(() {});
    _scrollToBottom();
  }

  /// 滚动到最新消息；进入页面时用 [animated: false] 立即跳到底部
  void _scrollToBottom({bool animated = true, int attempt = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (!_scrollController.hasClients) {
        if (attempt < 5) {
          _scrollToBottom(animated: animated, attempt: attempt + 1);
        }
        return;
      }
      final target = _scrollController.position.maxScrollExtent;
      if (target <= 0 && attempt < 5) {
        _scrollToBottom(animated: animated, attempt: attempt + 1);
        return;
      }
      if (animated) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(target);
      }
    });
  }

  Future<void> _showApprovalDialog() async {
    final request = widget.viewModel.pendingApproval;
    if (request == null || !mounted) {
      _showingApproval = false;
      return;
    }
    final choice = await ApprovalDialog.show(context, request);
    if (!mounted) {
      return;
    }
    widget.viewModel.resolveApproval(choice);
    _showingApproval = false;
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    final isBusy = vm.isBusy;
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    if (inset != _keyboardInset) {
      final opening = _keyboardInset == 0 && inset > 0;
      _keyboardInset = inset;
      if (opening) {
        _scrollToBottomAfterKeyboard();
      }
    }

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Row(
          children: [
            ServerIconAvatar(iconKey: _serverIconKey, radius: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                vm.currentSession?.title ?? widget.serverName,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (!widget.isServerOnline)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Theme.of(context).colorScheme.errorContainer,
              child: Text(
                '服务器离线，可查看记录；发送消息需恢复连接',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: vm.messages.length + (isBusy ? 1 : 0),
              itemBuilder: (context, index) {
                if (index < vm.messages.length) {
                  return MessageBubble(
                    message: vm.messages[index],
                    userAvatarPath: AppConfig.userAvatarPath,
                    userNickname: AppConfig.nickname,
                  );
                }
                return _buildStreamingBubble(vm);
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (vm.toolProgressMessage != null)
              ToolProgressBar(message: vm.toolProgressMessage!),
            _buildInputBar(vm, isBusy),
          ],
        ),
      ),
    );
  }

  Widget _buildStreamingBubble(ChatViewModel vm) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (vm.streamingReasoning.isNotEmpty)
            ThinkingSection(
              reasoningText: vm.streamingReasoning,
              isStreaming: vm.chatState == ChatState.reasoning,
            ),
          if (vm.streamingContent.isNotEmpty)
            StreamingText(text: vm.streamingContent)
          else if (vm.chatState == ChatState.thinking ||
              vm.chatState == ChatState.awaitingApproval)
            Text(
              vm.chatState == ChatState.awaitingApproval ? '等待审批...' : '思考中...',
            ),
        ],
      ),
    );
  }

  Widget _buildInputBar(ChatViewModel vm, bool isBusy) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: _buildTextField(isBusy, theme)),
                if (isBusy)
                  IconButton(
                    icon: Icon(Icons.stop_circle, color: theme.colorScheme.error),
                    tooltip: '停止生成',
                    onPressed: vm.stopGeneration,
                  )
                else if (_hasText)
                  IconButton(
                    icon: Icon(Icons.send, color: theme.colorScheme.primary),
                    tooltip: '发送',
                    onPressed: _sendTextMessage,
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    tooltip: '更多',
                    onPressed: isBusy ? null : _showAttachmentPanel,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(bool isBusy, ThemeData theme) {
    return TextField(
      controller: _textController,
      focusNode: _inputFocusNode,
      enabled: !isBusy,
      minLines: 1,
      maxLines: 5,
      textInputAction: TextInputAction.send,
      onSubmitted: isBusy ? null : (_) => _sendTextMessage(),
      decoration: InputDecoration(
        hintText: '输入消息',
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        isDense: true,
      ),
    );
  }

  void _sendTextMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty || widget.viewModel.isBusy) {
      return;
    }
    widget.viewModel.sendTextMessage(text);
    _textController.clear();
  }

  void _showAttachmentPanel() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) => ChatAttachmentPanel(
        onCamera: () => _pickImage(ImageSource.camera),
        onGallery: () => _pickImage(ImageSource.gallery),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final base64 = await _imageService.pickAndCompress(source: source);
    if (base64 == null || !mounted) {
      return;
    }
    await widget.viewModel.sendImageMessage(
      text: _textController.text.trim(),
      imageBase64s: [base64],
    );
    _textController.clear();
  }
}
