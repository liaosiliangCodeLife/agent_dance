import 'dart:convert';

import 'package:agent_dance/agents/database/app_database.dart';
import 'package:agent_dance/agents/models/session.dart';
import 'package:agent_dance/agents/repositories/chat_repository.dart';
import 'package:agent_dance/services/background_task_service.dart';
import 'package:agent_dance/services/chat_task_registry.dart';
import 'package:agent_dance/ui/chatui/chat_screen.dart';
import 'package:agent_dance/utils/logger.dart';
import 'package:flutter/material.dart';

/// 全局应用服务：仓库、导航、通知跳转
class AppServices {
  AppServices._(this.db);

  static AppServices? _instance;
  static AppServices get instance {
    final s = _instance;
    if (s == null) {
      throw StateError('AppServices 尚未初始化');
    }
    return s;
  }

  final AppDatabase db;
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  final _log = Logger('AppServices');

  late final ServerRepository serverRepository;
  late final SessionRepository sessionRepository;
  late final ChatRepository chatRepository;

  String? _pendingNotificationPayload;

  static Future<AppServices> init(AppDatabase db) async {
    final services = AppServices._(db);
    services._initRepositories();
    _instance = services;
    await BackgroundTaskService.init();
    return services;
  }

  void _initRepositories() {
    serverRepository = ServerRepository(db);
    sessionRepository = SessionRepository(db);
    chatRepository = ChatRepository(db, sessionRepository, serverRepository);
  }

  void handleNotificationPayload(String payload) {
    _pendingNotificationPayload = payload;
    _tryOpenChatFromPayload();
  }

  void onAppReady() {
    BackgroundTaskService.instance.setAppInForeground(true);
    _tryOpenChatFromPayload();
  }

  Future<void> openChat({
    required String serverId,
    required String serverName,
    String? sessionId,
    String? sessionTitle,
  }) async {
    final server = await serverRepository.getServerById(serverId);
    if (server == null) {
      _log.warn('服务器不存在', {'serverId': serverId});
      return;
    }

    Session? session;
    if (sessionId != null && sessionId.isNotEmpty) {
      session = await sessionRepository.getSessionById(sessionId);
    }
    session ??= (await sessionRepository.getSessionsByServer(serverId)).firstOrNull;
    session ??= await sessionRepository.createSession(serverId: serverId);

    final vm = ChatTaskRegistry.getOrCreate(
      sessionId: session.id,
      serverId: serverId,
      serverName: serverName,
      sessionTitle: session.title,
      chatRepository: chatRepository,
      sessionRepository: sessionRepository,
    );
    await vm.init();
    vm.attachUi();

    final nav = navigatorKey.currentState;
    if (nav == null) {
      _log.warn('导航器未就绪，无法打开对话', {'serverId': serverId, 'sessionId': session.id});
      return;
    }

    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          viewModel: vm,
          serverId: serverId,
          serverName: serverName,
          sessionTitle: session!.title,
          serverIconKey: server.iconKey,
          isServerOnline: server.isOnline,
          sessionRepository: sessionRepository,
          chatRepository: chatRepository,
        ),
      ),
    );
  }

  void _tryOpenChatFromPayload() {
    final payload = _pendingNotificationPayload;
    if (payload == null || payload.isEmpty) {
      return;
    }
    if (navigatorKey.currentState == null) {
      return;
    }
    _pendingNotificationPayload = null;

    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final serverId = data['serverId']?.toString();
      final sessionId = data['sessionId']?.toString();
      final serverName = data['serverName']?.toString() ?? '智能体';
      if (serverId == null || serverId.isEmpty) {
        return;
      }
      openChat(serverId: serverId, serverName: serverName, sessionId: sessionId);
    } catch (e, st) {
      _log.error('解析通知 payload 失败', e, st);
    }
  }
}
