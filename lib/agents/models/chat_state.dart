/// 聊天状态机
enum ChatState {
  idle,
  thinking,
  reasoning,
  streaming,
  awaitingApproval,
}

/// SSE 事件基类
sealed class SseEvent {}

/// 思考过程 token
class SseReasoning extends SseEvent {
  SseReasoning({required this.text});
  final String text;
}

/// 正文 token
class SseToken extends SseEvent {
  SseToken({required this.text});
  final String text;
}

/// 工具执行进度
class SseToolProgress extends SseEvent {
  SseToolProgress({required this.message});
  final String message;
}

/// 流结束
class SseDone extends SseEvent {}

/// 指令审批请求（Runs API）
class SseApprovalRequest extends SseEvent {
  SseApprovalRequest({
    required this.runId,
    required this.command,
    required this.description,
    required this.choices,
  });

  final String runId;
  final String command;
  final String description;
  final List<String> choices;
}

/// 审批选项
enum ApprovalChoice {
  once('once', '允许本次'),
  session('session', '本次会话'),
  always('always', '始终允许'),
  deny('deny', '拒绝');

  const ApprovalChoice(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static ApprovalChoice? fromApiValue(String value) {
    for (final c in ApprovalChoice.values) {
      if (c.apiValue == value) {
        return c;
      }
    }
    return null;
  }
}

/// 智能体服务器类型
enum AgentType {
  hermes('Hermes'),
  claudeCode('Claude Code'),
  custom('自定义');

  const AgentType(this.label);
  final String label;

  static AgentType fromString(String value) {
    return AgentType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => AgentType.custom,
    );
  }
}

/// 网络连通性状态
enum NetworkReachability {
  lan('局域网可达'),
  tunnel('需穿透'),
  unreachable('不可达');

  const NetworkReachability(this.label);
  final String label;
}
