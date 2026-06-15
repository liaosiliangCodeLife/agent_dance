import 'package:agent_dance/agents/models/chat_state.dart';

/// 智能体服务器节点
class AgentServer {
  const AgentServer({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.agentType,
    required this.createdAt,
    required this.updatedAt,
    this.iconKey = 'emoji:🤖',
    this.isOnline = false,
    this.latencyMs,
  });

  final String id;
  final String name;
  final String host;
  final int port;
  final AgentType agentType;
  final String iconKey;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isOnline;
  final int? latencyMs;

  String get baseUrl {
    final trimmed = host.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      final uri = Uri.parse(trimmed);
      if (uri.hasPort) {
        return trimmed;
      }
      return '$trimmed:$port';
    }
    return 'http://$trimmed:$port';
  }

  AgentServer copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    AgentType? agentType,
    String? iconKey,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isOnline,
    int? latencyMs,
  }) {
    return AgentServer(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      agentType: agentType ?? this.agentType,
      iconKey: iconKey ?? this.iconKey,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isOnline: isOnline ?? this.isOnline,
      latencyMs: latencyMs ?? this.latencyMs,
    );
  }
}

/// 局域网发现的智能体节点
class DiscoveredAgent {
  const DiscoveredAgent({
    required this.name,
    required this.host,
    required this.port,
  });

  final String name;
  final String host;
  final int port;
}
