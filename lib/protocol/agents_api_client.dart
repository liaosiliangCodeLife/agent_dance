import 'dart:async';
import 'dart:convert';

import 'package:agent_dance/agents/models/chat_state.dart';
import 'package:agent_dance/config/app_config.dart';
import 'package:agent_dance/utils/logger.dart';
import 'package:http/http.dart' as http;

/// Agents HTTP 客户端
class AgentsApiClient {
  AgentsApiClient({
    required this.baseUrl,
    required this.apiKey,
    this.model = AppConfig.defaultModel,
  });

  final String baseUrl;
  final String apiKey;
  final String model;
  final _log = Logger('AgentsApiClient');

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      };

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  /// 健康检查，返回延迟毫秒数
  Future<int?> healthCheck() async {
    final stopwatch = Stopwatch()..start();
    try {
      final response = await http
          .get(_uri('/health'), headers: _headers)
          .timeout(const Duration(seconds: 5));
      stopwatch.stop();
      if (response.statusCode == 200) {
        return stopwatch.elapsedMilliseconds;
      }
      return null;
    } catch (e, st) {
      _log.warn('健康检查失败', {'baseUrl': baseUrl, 'error': e.toString(), 'stack': st.toString()});
      return null;
    }
  }

  /// 非流式对话补全
  Future<String> chatCompletion({
    required List<Map<String, dynamic>> messages,
  }) async {
    final body = jsonEncode({
      'model': model,
      'messages': messages,
      'stream': false,
    });
    final response = await http
        .post(
          _uri('/v1/chat/completions'),
          headers: _headers,
          body: body,
        )
        .timeout(const Duration(seconds: 120));

    if (response.statusCode == 401) {
      throw AgentsApiException('API 密钥无效，请重新配置', statusCode: 401);
    }
    if (response.statusCode >= 500) {
      throw AgentsApiException('服务暂不可用', statusCode: response.statusCode);
    }
    if (response.statusCode != 200) {
      throw AgentsApiException('请求失败: ${response.statusCode}', statusCode: response.statusCode);
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = json['choices'] as List<dynamic>?;
    final message = choices?.first['message'] as Map<String, dynamic>?;
    return message?['content']?.toString() ?? '';
  }

  /// 流式对话
  Stream<SseEvent> streamChat({
    required List<Map<String, dynamic>> messages,
    String? sessionId,
    String? sessionKey,
    http.Client? client,
  }) {
    final sseClient = AgentsSseClient(
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      client: client,
    );
    return sseClient.streamChat(
      messages: messages,
      sessionId: sessionId,
      sessionKey: sessionKey,
    );
  }

  /// 启动 Runs（文本对话优先，支持指令审批）
  Future<String> startRun({
    required String sessionKey,
    required String input,
    required List<Map<String, dynamic>> conversationHistory,
    required String sessionId,
  }) async {
    _log.info('Runs API 请求', {
      'sessionId': sessionId,
      'sessionKey': sessionKey,
      'historyLen': conversationHistory.length,
    });
    final response = await http
        .post(
          _uri('/v1/runs'),
          headers: {
            ..._headers,
            'X-Hermes-Session-Id': sessionId,
            'X-Hermes-Session-Key': sessionKey,
          },
          body: jsonEncode({
            'input': input,
            'conversation_history': conversationHistory,
            'session_id': sessionId,
          }),
        )
        .timeout(const Duration(seconds: 30));

    _checkResponse(response);
    if (response.statusCode != 200 && response.statusCode != 202) {
      throw AgentsApiException('Runs API 不可用: ${response.statusCode}', statusCode: response.statusCode);
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final runId = json['run_id']?.toString();
    if (runId == null || runId.isEmpty) {
      throw AgentsApiException('Runs API 未返回 run_id');
    }
    return runId;
  }

  /// 订阅 Run 事件流
  Stream<SseEvent> streamRunEvents(String runId, {http.Client? client}) {
    final sseClient = AgentsSseClient(
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      client: client,
    );
    return sseClient.streamRunEvents(runId);
  }

  /// 提交审批结果
  Future<void> submitApproval({
    required String runId,
    required String choice,
  }) async {
    final response = await http
        .post(
          _uri('/v1/runs/$runId/approval'),
          headers: _headers,
          body: jsonEncode({'choice': choice}),
        )
        .timeout(const Duration(seconds: 15));
    _checkResponse(response);
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw AgentsApiException('审批提交失败: ${response.statusCode}', statusCode: response.statusCode);
    }
  }

  void _checkResponse(http.Response response) {
    if (response.statusCode == 401) {
      throw AgentsApiException('API 密钥无效，请重新配置', statusCode: 401);
    }
    if (response.statusCode >= 500) {
      throw AgentsApiException('服务暂不可用', statusCode: response.statusCode);
    }
  }
}

/// SSE 流式客户端
class AgentsSseClient {
  AgentsSseClient({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final String apiKey;
  final String model;
  final http.Client _client;
  final _log = Logger('AgentsSseClient');

  Stream<SseEvent> streamChat({
    required List<Map<String, dynamic>> messages,
    String? sessionId,
    String? sessionKey,
  }) async* {
    final request = http.Request('POST', Uri.parse('$baseUrl/v1/chat/completions'));
    final headers = <String, String>{
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
    };
    if (sessionId != null && sessionId.isNotEmpty) {
      headers['X-Hermes-Session-Id'] = sessionId;
    }
    if (sessionKey != null && sessionKey.isNotEmpty) {
      headers['X-Hermes-Session-Key'] = sessionKey;
    }
    _log.info('Chat Completions 请求', {
      'sessionId': sessionId ?? '',
      'sessionKey': sessionKey ?? '',
      'messageCount': messages.length,
    });
    request.headers.addAll(headers);
    request.body = jsonEncode({
      'model': model,
      'messages': messages,
      'stream': true,
    });

    http.StreamedResponse response;
    try {
      response = await _client.send(request).timeout(const Duration(seconds: 30));
    } catch (e) {
      throw AgentsApiException('无法连接服务器');
    }

    if (response.statusCode == 401) {
      throw AgentsApiException('API 密钥无效，请重新配置', statusCode: 401);
    }
    if (response.statusCode != 200) {
      throw AgentsApiException('请求失败: ${response.statusCode}', statusCode: response.statusCode);
    }

    String? currentEvent;
    final buffer = StringBuffer();
    var accumulatedContent = '';
    var accumulatedReasoning = '';

    await for (final chunk in response.stream.transform(utf8.decoder)) {
      buffer.write(chunk);
      final content = buffer.toString();
      final lines = content.split('\n');
      buffer.clear();
      if (!content.endsWith('\n')) {
        buffer.write(lines.removeLast());
      }

      for (final rawLine in lines) {
        final line = rawLine.trimRight();
        if (line.isEmpty) {
          currentEvent = null;
          continue;
        }
        if (line.startsWith('event: ')) {
          currentEvent = line.substring(7).trim();
          continue;
        }
        if (!line.startsWith('data: ')) {
          continue;
        }

        final data = line.substring(6);
        if (data == '[DONE]') {
          yield SseDone();
          return;
        }

        try {
          if (currentEvent == 'hermes.tool.progress' ||
              currentEvent == 'agents.tool.progress') {
            final tool = jsonDecode(data) as Map<String, dynamic>;
            yield SseToolProgress(message: tool['message']?.toString() ?? '工具执行中...');
            currentEvent = null;
            continue;
          }

          final chunkJson = jsonDecode(data) as Map<String, dynamic>;
          final choices = chunkJson['choices'] as List<dynamic>?;
          if (choices == null || choices.isEmpty) {
            continue;
          }
          final choice = choices.first as Map<String, dynamic>;
          final delta = choice['delta'] as Map<String, dynamic>?;
          if (delta == null) {
            continue;
          }

          final reasoning = delta['reasoning_content']?.toString();
          if (reasoning != null && reasoning.isNotEmpty) {
            final reasoningInc = takeStreamingIncrement(reasoning, accumulatedReasoning);
            accumulatedReasoning = reasoningInc.$1;
            if (reasoningInc.$2 != null) {
              yield SseReasoning(text: reasoningInc.$2!);
              await _yieldFrame();
            }
          }

          final contentToken = delta['content']?.toString();
          if (contentToken != null && contentToken.isNotEmpty) {
            final contentInc = takeStreamingIncrement(contentToken, accumulatedContent);
            accumulatedContent = contentInc.$1;
            if (contentInc.$2 != null) {
              yield SseToken(text: contentInc.$2!);
              await _yieldFrame();
            }
          }
        } catch (e, st) {
          _log.warn('SSE 解析失败', {'line': line, 'error': e.toString(), 'stack': st.toString()});
        }
      }
    }
    yield SseDone();
  }

  /// Runs API 事件流
  Stream<SseEvent> streamRunEvents(String runId) async* {
    final request = http.Request('GET', Uri.parse('$baseUrl/v1/runs/$runId/events'));
    request.headers.addAll({
      'Authorization': 'Bearer $apiKey',
      'Accept': 'text/event-stream',
    });

    http.StreamedResponse response;
    try {
      response = await _client.send(request).timeout(const Duration(seconds: 30));
    } catch (e) {
      throw AgentsApiException('无法连接服务器');
    }

    if (response.statusCode == 401) {
      throw AgentsApiException('API 密钥无效，请重新配置', statusCode: 401);
    }
    if (response.statusCode != 200) {
      throw AgentsApiException('Run 事件流失败: ${response.statusCode}', statusCode: response.statusCode);
    }

    final buffer = StringBuffer();
    var accumulatedContent = '';
    var accumulatedReasoning = '';

    await for (final chunk in response.stream.transform(utf8.decoder)) {
      buffer.write(chunk);
      final content = buffer.toString();
      final lines = content.split('\n');
      buffer.clear();
      if (!content.endsWith('\n')) {
        buffer.write(lines.removeLast());
      }

      for (final rawLine in lines) {
        final line = rawLine.trimRight();
        if (line.isEmpty || !line.startsWith('data: ')) {
          continue;
        }

        final data = line.substring(6);
        if (data == '[DONE]') {
          yield SseDone();
          return;
        }

        try {
          final eventJson = jsonDecode(data) as Map<String, dynamic>;
          final eventType = eventJson['event']?.toString() ?? '';

          switch (eventType) {
            case 'approval.request':
              yield SseApprovalRequest(
                runId: eventJson['run_id']?.toString() ?? runId,
                command: eventJson['command']?.toString() ?? '',
                description: eventJson['description']?.toString() ?? '',
                choices: (eventJson['choices'] as List<dynamic>?)
                        ?.map((e) => e.toString())
                        .toList() ??
                    ApprovalChoice.values.map((e) => e.apiValue).toList(),
              );
              break;
            case 'message.delta':
              final delta = eventJson['delta']?.toString() ??
                  eventJson['text']?.toString() ??
                  eventJson['content']?.toString() ??
                  '';
              final contentInc = takeStreamingIncrement(delta, accumulatedContent);
              accumulatedContent = contentInc.$1;
              if (contentInc.$2 != null) {
                yield SseToken(text: contentInc.$2!);
                await _yieldFrame();
              }
              break;
            case 'reasoning.available':
              final text = eventJson['text']?.toString() ??
                  eventJson['reasoning']?.toString() ??
                  '';
              final reasoningInc = takeStreamingIncrement(text, accumulatedReasoning);
              accumulatedReasoning = reasoningInc.$1;
              if (reasoningInc.$2 != null) {
                yield SseReasoning(text: reasoningInc.$2!);
                await _yieldFrame();
              }
              break;
            case 'hermes.tool.progress':
            case 'agents.tool.progress':
            case 'tool.progress':
              yield SseToolProgress(
                message: eventJson['message']?.toString() ?? '工具执行中...',
              );
              break;
            case 'run.completed':
              var output = eventJson['output']?.toString() ?? '';
              // 兜底：推理模型答案全放 reasoning，output 为空
              if (output.isEmpty &&
                  accumulatedContent.isEmpty &&
                  accumulatedReasoning.isNotEmpty) {
                output = accumulatedReasoning;
              }
              final outputInc = takeStreamingIncrement(output, accumulatedContent);
              accumulatedContent = outputInc.$1;
              if (outputInc.$2 != null) {
                yield SseToken(text: outputInc.$2!);
                await _yieldFrame();
              }
              yield SseDone();
              return;
            default:
              break;
          }
        } catch (e, st) {
          _log.warn('Run SSE 解析失败', {'line': line, 'error': e.toString(), 'stack': st.toString()});
        }
      }
    }
    yield SseDone();
  }

  void dispose() {
    _client.close();
  }
}

/// 兼容增量 token 与累计全文两种流式格式
(String accumulated, String? suffix) takeStreamingIncrement(
  String incoming,
  String accumulated,
) {
  if (incoming.isEmpty) {
    return (accumulated, null);
  }
  if (accumulated.isEmpty) {
    return (incoming, incoming);
  }
  if (incoming.startsWith(accumulated)) {
    final suffix = incoming.substring(accumulated.length);
    return (incoming, suffix.isEmpty ? null : suffix);
  }
  return (accumulated + incoming, incoming);
}

/// 让出事件循环，使 UI 有机会逐帧刷新流式文本
Future<void> _yieldFrame() => Future<void>.delayed(Duration.zero);

/// API 异常
class AgentsApiException implements Exception {
  AgentsApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
