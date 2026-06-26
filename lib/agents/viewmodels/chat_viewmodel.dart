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

/// 会话级聊天 ViewModel
class ChatViewModel extends ChangeNotifier {
  ChatViewModel({
    required ChatRepository chatRepository,
    required SessionRepository sessionRepository,
    required String sessionId,
    required String serverId,
    required this.serverName,
    required this.sessionTitle,
  })  : _chatRepository = chatRepository,
        _sessionRepository = sessionRepository,
        _sessionId = sessionId,
        _serverId = serverId;

  final ChatRepository _chatRepository;
  final SessionRepository _sessionRepository;
  final String _sessionId;
  final String _serverId;
  final String serverName;
  String sessionTitle;
  final _log = Logger('ChatViewModel');

  List<Message> messages = [];
  String streamingReasoning = '';
  String streamingContent = '';
  ChatState chatState = ChatState.idle;
  String? toolProgressMessage;
  String? errorMessage;
  Session? currentSession;
  SseApprovalRequest? pendingApproval;

  /// F-139：思考中读秒
  final ValueNotifier<String> thinkingLabel = ValueNotifier('');
  Timer? _thinkingTimer;
  double _thinkingSeconds = 0;

  StreamSubscription<SseEvent>? _streamSub;
  Completer<ApprovalChoice>? _approvalCompleter;
  Timer? _backgroundApprovalTimer;
  bool _disposed = false;
  bool _approvalDialogVisible = false;
  bool _uiAttached = false;
  bool _isFinishingStream = false;

  String get sessionId => _sessionId;
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
    currentSession = await _sessionRepository.getSessionById(_sessionId);
    if (currentSession != null) {
      sessionTitle = currentSession!.title;
    }
    _log.info('进入会话', {'sessionId': _sessionId, 'title': sessionTitle});
    if (!isBusy) {
      messages = await _chatRepository.loadMessages(_sessionId);
    }
    await _sessionRepository.clearUnread(_sessionId);
    notifyListeners();
  }

  Future<void> updateSessionTitle(String title) async {
    sessionTitle = title;
    await _sessionRepository.updateSessionTitle(_sessionId, title);
    currentSession = await _sessionRepository.getSessionById(_sessionId);
    notifyListeners();
  }

  Future<void> sendTextMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || isBusy) {
      return;
    }
    await _sendInternal(() async {
      final userMsg = await _chatRepository.saveUserMessage(
        sessionId: _sessionId,
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
        sessionId: _sessionId,
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

  void _startThinkingTimer() {
    _thinkingSeconds = 0;
    _thinkingTimer?.cancel();
    thinkingLabel.value = '思考中(0.0s).....';
    _thinkingTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _thinkingSeconds += 0.1;
      thinkingLabel.value = '思考中(${_thinkingSeconds.toStringAsFixed(1)}s).....';
    });
  }

  void _stopThinkingTimer() {
    _thinkingTimer?.cancel();
    _thinkingTimer = null;
    thinkingLabel.value = '';
  }

  Future<void> _startStream({
    required Map<String, dynamic> currentUserMessage,
    String? userInputForRuns,
  }) async {
    await _streamSub?.cancel();
    _isFinishingStream = false;
    _startThinkingTimer();
    unawaited(
      BackgroundTaskService.instance.onTaskStarted(
        sessionId: _sessionId,
        serverId: _serverId,
        title: sessionTitle.isNotEmpty ? sessionTitle : serverName,
      ),
    );

    // 构建历史（不含刚追加的当前 user 消息，当前轮由 currentUserMessage / userInputForRuns 携带）
    final conversationHistory = <Map<String, dynamic>>[];
    for (var i = 0; i < messages.length - 1; i++) {
      final m = messages[i];
      if (m.role == 'user') {
        conversationHistory.add({'role': 'user', 'content': m.content});
      } else if (m.role == 'assistant') {
        conversationHistory.add({'role': 'assistant', 'content': m.content});
      }
    }
    _log.info('发送消息', {
      'sessionId': _sessionId,
      'serverId': _serverId,
      'historyLen': conversationHistory.length,
    });

    _streamSub = _chatRepository
        .streamReply(
          serverId: _serverId,
          sessionId: _sessionId,
          currentUserMessage: currentUserMessage,
          userInputForRuns: userInputForRuns,
          conversationHistory: conversationHistory,
        )
        .listen(
      (event) {
        if (_disposed) {
          return;
        }
        if (event is SseReasoning) {
          _stopThinkingTimer();
          if (chatState == ChatState.thinking || chatState == ChatState.awaitingApproval) {
            chatState = ChatState.reasoning;
          }
          streamingReasoning += event.text;
          notifyListeners();
        } else if (event is SseToken) {
          _stopThinkingTimer();
          chatState = ChatState.streaming;
          streamingContent += event.text;
          notifyListeners();
        } else if (event is SseToolProgress) {
          toolProgressMessage = event.message;
          unawaited(
            BackgroundTaskService.instance.onTaskProgress(
              sessionId: _sessionId,
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
        _stopThinkingTimer();
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
    _stopThinkingTimer();
    try {
      if (streamingContent.isEmpty && streamingReasoning.isEmpty) {
        chatState = ChatState.idle;
        unawaited(BackgroundTaskService.instance.onTaskStopped());
        notifyListeners();
        return;
      }
      // 兜底：推理模型答案全放 reasoning，content 为空
      final displayContent =
          streamingContent.isEmpty ? streamingReasoning : streamingContent;
      final assistant = await _chatRepository.saveAssistantMessage(
        sessionId: _sessionId,
        content: displayContent,
        reasoningText: streamingReasoning.isEmpty ? null : streamingReasoning,
      );
      messages.add(assistant);
      final preview = displayContent.length > 50
          ? displayContent.substring(0, 50)
          : displayContent;
      streamingReasoning = '';
      streamingContent = '';
      toolProgressMessage = null;
      chatState = ChatState.idle;
      notifyListeners();

      unawaited(
        BackgroundTaskService.instance.onTaskFinished(
          sessionId: _sessionId,
          serverId: _serverId,
          serverTitle: sessionTitle.isNotEmpty ? sessionTitle : serverName,
          preview: preview,
          uiAttached: _uiAttached,
        ),
      );
      ChatTaskRegistry.onTaskFinished(_sessionId);
    } finally {
      _isFinishingStream = false;
    }
  }

  void stopGeneration() {
    _streamSub?.cancel();
    _stopThinkingTimer();
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
    _stopThinkingTimer();
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
    _stopThinkingTimer();
    _backgroundApprovalTimer?.cancel();
    _streamSub?.cancel();
    if (_approvalCompleter != null && !_approvalCompleter!.isCompleted) {
      _approvalCompleter!.complete(ApprovalChoice.deny);
    }
  }

  @override
  void dispose() {
    disposeInternal();
    thinkingLabel.dispose();
    super.dispose();
  }
}
