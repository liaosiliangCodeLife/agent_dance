import 'dart:async';

import 'package:agent_dance/agents/models/chat_state.dart';
import 'package:agent_dance/agents/repositories/chat_repository.dart';
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
    required this.serverId,
    required this.serverName,
    required this.sessionTitle,
    this.serverIconKey,
    this.isServerOnline = true,
    required this.sessionRepository,
    required this.chatRepository,
  });

  final ChatViewModel viewModel;
  final String serverId;
  final String serverName;
  final String sessionTitle;
  final String? serverIconKey;
  final bool isServerOnline;
  final SessionRepository sessionRepository;
  final ChatRepository chatRepository;

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
    AppConfig.userProfile.addListener(_onUserProfileChanged);
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

  void _onUserProfileChanged() {
    if (mounted) {
      setState(() {});
    }
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
        .getServerById(widget.serverId);
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
    AppConfig.userProfile.removeListener(_onUserProfileChanged);
    _textController.removeListener(_onTextChanged);
    _inputFocusNode.removeListener(_onInputFocusChanged);
    _inputFocusNode.dispose();
    _textController.dispose();
    ChatTaskRegistry.onScreenClosed(widget.viewModel.sessionId);
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
      // 手动用 viewInsets 顶起输入栏，避免 bottomNavigationBar 被键盘盖住
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: GestureDetector(
          onTap: _showSessionSwitcher,
          onLongPress: _renameCurrentSession,
          child: Row(
            children: [
              ServerIconAvatar(iconKey: _serverIconKey, radius: 16),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  vm.sessionTitle.isNotEmpty ? vm.sessionTitle : widget.sessionTitle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.arrow_drop_down, size: 20),
            ],
          ),
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
          AnimatedPadding(
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
            padding: EdgeInsets.only(bottom: inset),
            child: SafeArea(
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
          ),
        ],
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
          ValueListenableBuilder<String>(
            valueListenable: vm.thinkingLabel,
            builder: (_, label, __) => label.isEmpty
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
          ),
          if (vm.streamingReasoning.isNotEmpty)
            ThinkingSection(
              reasoningText: vm.streamingReasoning,
              isStreaming: vm.chatState == ChatState.reasoning,
            ),
          if (vm.streamingContent.isNotEmpty)
            StreamingText(text: vm.streamingContent)
          else if (vm.streamingReasoning.isNotEmpty)
            StreamingText(text: vm.streamingReasoning)
          else if (vm.chatState == ChatState.awaitingApproval)
            const Text('等待审批...'),
        ],
      ),
    );
  }

  Future<void> _renameCurrentSession() async {
    final controller = TextEditingController(text: widget.viewModel.sessionTitle);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改会话标题'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入新标题'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newTitle != null && newTitle.isNotEmpty && mounted) {
      await widget.viewModel.updateSessionTitle(newTitle);
    }
  }

  Future<void> _showSessionSwitcher() async {
    final sessions = await widget.sessionRepository.getSessionsByServer(widget.serverId);
    if (!mounted) {
      return;
    }
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('切换会话 · ${widget.serverName}'),
              trailing: IconButton(
                icon: const Icon(Icons.add),
                onPressed: () => Navigator.pop(ctx, '__new__'),
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: sessions.length,
                itemBuilder: (context, index) {
                  final session = sessions[index];
                  final isCurrent = session.id == widget.viewModel.sessionId;
                  return ListTile(
                    title: Text(session.title),
                    subtitle: session.lastMessagePreview.isNotEmpty
                        ? Text(session.lastMessagePreview, maxLines: 1, overflow: TextOverflow.ellipsis)
                        : null,
                    trailing: isCurrent ? const Icon(Icons.check) : null,
                    onTap: () => Navigator.pop(ctx, session.id),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) {
      return;
    }
    if (selected == '__new__') {
      final session = await widget.sessionRepository.createSession(serverId: widget.serverId);
      if (!mounted) {
        return;
      }
      _switchToSession(session.id, session.title);
      return;
    }
    if (selected != widget.viewModel.sessionId) {
      final session = sessions.firstWhere((s) => s.id == selected);
      _switchToSession(session.id, session.title);
    }
  }

  void _switchToSession(String sessionId, String sessionTitle) {
    final chatVm = ChatTaskRegistry.getOrCreate(
      sessionId: sessionId,
      serverId: widget.serverId,
      serverName: widget.serverName,
      sessionTitle: sessionTitle,
      chatRepository: widget.chatRepository,
      sessionRepository: widget.sessionRepository,
    );
    unawaited(chatVm.init().then((_) {
      if (!mounted) {
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ChatScreen(
            viewModel: chatVm,
            serverId: widget.serverId,
            serverName: widget.serverName,
            sessionTitle: sessionTitle,
            serverIconKey: widget.serverIconKey ?? _serverIconKey,
            isServerOnline: widget.isServerOnline,
            sessionRepository: widget.sessionRepository,
            chatRepository: widget.chatRepository,
          ),
        ),
      );
    }));
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
