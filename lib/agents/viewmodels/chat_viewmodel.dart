import 'dart:async';

import 'package:agent_dance/agents/models/chat_state.dart';
import 'package:agent_dance/agents/models/message.dart';
import 'package:agent_dance/agents/models/session.dart';
import 'package:agent_dance/agents/repositories/chat_repository.dart' show ChatRepository, SessionRepository;
import 'package:agent_dance/protocol/agents_api_client.dart';
import 'package:agent_dance/services/background_task_service.dart';
import 'package:agent_dance/services/chat_task_registry.dart';
import 'package:agent_dance/ui/chatui/widgets/approval_dialog.dart';
import 'package:agent_dance/utils/logger.dart';
import 'package:flutter/foundation.dart';

/// 服务器级聊天 ViewModel（F-127）
/// API 每次只发当前一条 user 消息（F-126）；UI/本地 SQLite 保留完整对话记录。
class ChatViewModel extends ChangeNotifier {
  ChatViewModel({
    required ChatRepository chatRepository,
    required SessionRepository sessionRepository,
    required String serverId,
    required this.serverName,
  })  : _chatRepository = chatRepository,
        _sessionRepository = sessionRepository,
        _serverId = serverId;

  final ChatRepository _chatRepository;
  final SessionRepository _sessionRepository;
  final String _serverId;
  final String serverName;
  final _log = Logger('ChatViewModel');

  List<Message> messages = [];
  String streamingReasoning = '';
  String streamingContent = '';
  ChatState chatState = ChatState.idle;
  String? toolProgressMessage;
  String? errorMessage;
  Session? currentSession;
  SseApprovalRequest? pendingApproval;

  StreamSubscription<SseEvent>? _streamSub;
  Completer<ApprovalChoice>? _approvalCompleter;
  Timer? _backgroundApprovalTimer;
  bool _disposed = false;
  bool _approvalDialogVisible = false;
  bool _uiAttached = false;
  bool _isFinishingStream = false;

  String get serverId => _serverId;
  bool get uiAttached => _uiAttached;
  bool get isBusy => chatState != ChatState.idle;

  void attachUi() {
    _uiAttached = true;
    _backgroundApprovalTimer?.cancel();
  }

  void detachUi() {
    _uiAttached = false;
  }

  Future<void> init() async {
    currentSession = await _sessionRepository.ensureServerChat(
      serverId: _serverId,
      serverName: serverName,
    );
    if (!isBusy) {
      messages = await _chatRepository.loadMessages(_serverId);
    }
    await _sessionRepository.clearUnread(_serverId);
    notifyListeners();
  }

  Future<void> sendTextMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || isBusy) {
      return;
    }
    await _sendInternal(() async {
      final userMsg = await _chatRepository.saveUserMessage(
        serverId: _serverId,
        content: trimmed,
      );
      messages.add(userMsg);
      notifyListeners();
      final apiMessage = _chatRepository.buildCurrentApiMessage(content: trimmed);
      await _startStream(
        currentUserMessage: apiMessage,
        userInputForRuns: trimmed,
      );
    });
  }

  Future<void> sendImageMessage({
    required String text,
    required List<String> imageBase64s,
  }) async {
    if (isBusy) {
      return;
    }
    await _sendInternal(() async {
      final userMsg = await _chatRepository.saveUserMessage(
        serverId: _serverId,
        content: text,
        imageBase64s: imageBase64s,
      );
      messages.add(userMsg);
      notifyListeners();
      final apiMessage = _chatRepository.buildCurrentApiMessage(
        content: text,
        imageBase64s: imageBase64s,
      );
      await _startStream(currentUserMessage: apiMessage);
    });
  }

  Future<void> _sendInternal(Future<void> Function() action) async {
    errorMessage = null;
    chatState = ChatState.thinking;
    toolProgressMessage = null;
    streamingReasoning = '';
    streamingContent = '';
    notifyListeners();
    try {
      await action();
    } on AgentsApiException catch (e) {
      _handleError(e.message);
    } catch (e, st) {
      _log.error('发送消息失败', e, st);
      _handleError('发送失败，请稍后重试');
    }
  }

  Future<void> _startStream({
    required Map<String, dynamic> currentUserMessage,
    String? userInputForRuns,
  }) async {
    await _streamSub?.cancel();
    _isFinishingStream = false;
    unawaited(
      BackgroundTaskService.instance.onTaskStarted(
        serverId: _serverId,
        title: serverName,
      ),
    );

    _streamSub = _chatRepository
        .streamReply(
          serverId: _serverId,
          currentUserMessage: currentUserMessage,
          userInputForRuns: userInputForRuns,
        )
        .listen(
      (event) {
        if (_disposed) {
          return;
        }
        if (event is SseReasoning) {
          if (chatState == ChatState.thinking || chatState == ChatState.awaitingApproval) {
            chatState = ChatState.reasoning;
          }
          streamingReasoning += event.text;
          notifyListeners();
        } else if (event is SseToken) {
          chatState = ChatState.streaming;
          streamingContent += event.text;
          notifyListeners();
        } else if (event is SseToolProgress) {
          toolProgressMessage = event.message;
          unawaited(
            BackgroundTaskService.instance.onTaskProgress(
              serverId: _serverId,
              message: event.message,
            ),
          );
          notifyListeners();
        } else if (event is SseApprovalRequest) {
          unawaited(_handleApprovalRequest(event));
        } else if (event is SseDone) {
          unawaited(_finishStream());
        }
      },
      onError: (Object e, StackTrace st) {
        _log.error('流式接收失败', e, st);
        if (e is AgentsApiException) {
          _handleError(e.message);
        } else {
          _handleError('无法连接服务器');
        }
      },
    );
  }

  Future<void> _handleApprovalRequest(SseApprovalRequest event) async {
    chatState = ChatState.awaitingApproval;
    pendingApproval = event;
    _approvalCompleter = Completer<ApprovalChoice>();
    notifyListeners();

    if (!_uiAttached) {
      _backgroundApprovalTimer?.cancel();
      _backgroundApprovalTimer = Timer(ApprovalDialog.autoApproveTimeout, () {
        if (pendingApproval != null) {
          resolveApproval(ApprovalChoice.once);
        }
      });
    }

    final choice = await _approvalCompleter!.future;
    _backgroundApprovalTimer?.cancel();
    pendingApproval = null;
    _approvalDialogVisible = false;

    try {
      await _chatRepository.submitApproval(
        serverId: _serverId,
        runId: event.runId,
        choice: choice.apiValue,
      );
      if (!_disposed && chatState == ChatState.awaitingApproval) {
        chatState = ChatState.thinking;
        notifyListeners();
      }
    } catch (e, st) {
      _log.error('审批提交失败', e, st);
      _handleError('审批提交失败');
    }
  }

  void resolveApproval(ApprovalChoice choice) {
    if (_approvalCompleter != null && !_approvalCompleter!.isCompleted) {
      _approvalCompleter!.complete(choice);
    }
    _approvalCompleter = null;
  }

  bool get shouldShowApprovalDialog =>
      pendingApproval != null && !_approvalDialogVisible && _uiAttached;

  void markApprovalDialogVisible() {
    _approvalDialogVisible = true;
  }

  Future<void> _finishStream() async {
    if (_disposed || _isFinishingStream) {
      return;
    }
    if (chatState == ChatState.awaitingApproval) {
      return;
    }
    if (chatState == ChatState.idle &&
        streamingContent.isEmpty &&
        streamingReasoning.isEmpty) {
      return;
    }

    _isFinishingStream = true;
    try {
      if (streamingContent.isEmpty && streamingReasoning.isEmpty) {
        chatState = ChatState.idle;
        unawaited(BackgroundTaskService.instance.onTaskStopped());
        notifyListeners();
        return;
      }
      final assistant = await _chatRepository.saveAssistantMessage(
        serverId: _serverId,
        content: streamingContent,
        reasoningText: streamingReasoning.isEmpty ? null : streamingReasoning,
      );
      messages.add(assistant);
      final preview = streamingContent.length > 50
          ? streamingContent.substring(0, 50)
          : streamingContent;
      streamingReasoning = '';
      streamingContent = '';
      toolProgressMessage = null;
      chatState = ChatState.idle;
      notifyListeners();

      unawaited(
        BackgroundTaskService.instance.onTaskFinished(
          serverId: _serverId,
          serverTitle: serverName,
          preview: preview,
          uiAttached: _uiAttached,
        ),
      );
      ChatTaskRegistry.onTaskFinished(_serverId);
    } finally {
      _isFinishingStream = false;
    }
  }

  void stopGeneration() {
    _streamSub?.cancel();
    if (_approvalCompleter != null && !_approvalCompleter!.isCompleted) {
      _approvalCompleter!.complete(ApprovalChoice.deny);
    }
    _approvalCompleter = null;
    _backgroundApprovalTimer?.cancel();
    pendingApproval = null;
    unawaited(BackgroundTaskService.instance.onTaskStopped());
    if (streamingContent.isNotEmpty || streamingReasoning.isNotEmpty) {
      unawaited(_finishStream());
    } else {
      chatState = ChatState.idle;
      notifyListeners();
    }
  }

  void _handleError(String message) {
    errorMessage = message;
    chatState = ChatState.idle;
    streamingReasoning = '';
    streamingContent = '';
    toolProgressMessage = null;
    pendingApproval = null;
    _backgroundApprovalTimer?.cancel();
    if (_approvalCompleter != null && !_approvalCompleter!.isCompleted) {
      _approvalCompleter!.complete(ApprovalChoice.deny);
    }
    _approvalCompleter = null;
    unawaited(BackgroundTaskService.instance.onTaskStopped());
    notifyListeners();
  }

  void disposeInternal() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _backgroundApprovalTimer?.cancel();
    _streamSub?.cancel();
    if (_approvalCompleter != null && !_approvalCompleter!.isCompleted) {
      _approvalCompleter!.complete(ApprovalChoice.deny);
    }
  }

  @override
  void dispose() {
    disposeInternal();
    super.dispose();
  }
}
