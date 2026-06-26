import 'dart:convert';
import 'dart:io';

import 'package:agent_dance/services/app_services.dart';
import 'package:agent_dance/utils/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// 后台任务与完成通知（F-505 / F-506）
class BackgroundTaskService {
  BackgroundTaskService._();

  static final BackgroundTaskService instance = BackgroundTaskService._();
  static final _log = Logger('BackgroundTaskService');

  static const String _foregroundChannelId = 'agent_dance_running';
  static const String _completeChannelId = 'agent_dance_complete';
  static const int _completeNotificationBaseId = 9000;

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  String? _activeSessionId;
  bool _appInForeground = true;

  bool get appInForeground => _appInForeground;

  static Future<void> init() async {
    await instance._init();
  }

  Future<void> _init() async {
    if (_initialized) {
      return;
    }

    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      await _initForegroundTask();
      await _initNotifications();
    }
    _initialized = true;
    _log.info('后台任务服务已初始化');
  }

  Future<void> _initForegroundTask() async {
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _foregroundChannelId,
        channelName: 'Agent 运行中',
        channelDescription: '智能体任务后台执行',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  Future<void> _initNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    await _notifications.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    if (Platform.isAndroid) {
      final plugin = _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await plugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _completeChannelId,
          '任务完成',
          description: '智能体任务完成提醒',
          importance: Importance.high,
        ),
      );
      await plugin?.requestNotificationsPermission();
    }

    final launch = await _notifications.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      final payload = launch?.notificationResponse?.payload;
      if (payload != null && payload.isNotEmpty) {
        AppServices.instance.handleNotificationPayload(payload);
      }
    }
  }

  void setAppInForeground(bool value) {
    _appInForeground = value;
  }

  Future<void> onTaskStarted({
    required String sessionId,
    required String serverId,
    required String title,
  }) async {
    _activeSessionId = sessionId;
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      return;
    }
    try {
      await WakelockPlus.enable();
      if (!await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.startService(
          serviceId: 256,
          notificationTitle: '聚智',
          notificationText: title.isEmpty ? '智能体正在执行任务…' : '$title · 执行中',
          callback: _foregroundTaskCallback,
        );
      } else {
        await FlutterForegroundTask.updateService(
          notificationTitle: '聚智',
          notificationText: title.isEmpty ? '智能体正在执行任务…' : '$title · 执行中',
        );
      }
    } catch (e, st) {
      _log.warn('启动前台服务失败', {'error': e.toString(), 'stack': st.toString()});
    }
  }

  Future<void> onTaskProgress({
    required String sessionId,
    required String message,
  }) async {
    if (_activeSessionId != sessionId || kIsWeb) {
      return;
    }
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
          notificationTitle: '聚智',
          notificationText: message,
        );
      }
    } catch (_) {}
  }

  Future<void> onTaskFinished({
    required String sessionId,
    required String serverId,
    required String serverTitle,
    required String preview,
    required bool uiAttached,
  }) async {
    if (_activeSessionId == sessionId) {
      _activeSessionId = null;
    }
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      return;
    }
    try {
      await WakelockPlus.disable();
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (e, st) {
      _log.warn('停止前台服务失败', {'error': e.toString(), 'stack': st.toString()});
    }

    if (uiAttached && _appInForeground) {
      return;
    }
    await showCompletionNotification(
      sessionId: sessionId,
      serverId: serverId,
      serverTitle: serverTitle,
      preview: preview,
    );
  }

  Future<void> onTaskStopped() async {
    _activeSessionId = null;
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      return;
    }
    try {
      await WakelockPlus.disable();
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (_) {}
  }

  Future<void> showCompletionNotification({
    required String sessionId,
    required String serverId,
    required String serverTitle,
    required String preview,
  }) async {
    if (!_initialized) {
      return;
    }
    final payload = jsonEncode({
      'serverId': serverId,
      'sessionId': sessionId,
      'serverName': serverTitle,
    });
    final id = _completeNotificationBaseId + sessionId.hashCode.abs() % 10000;
    await _notifications.show(
      id,
      '任务已完成',
      preview.isEmpty ? serverTitle : preview,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _completeChannelId,
          '任务完成',
          channelDescription: '智能体任务完成提醒',
          importance: Importance.high,
          priority: Priority.high,
          ticker: '聚智 任务完成',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
        ),
      ),
      payload: payload,
    );
  }

  void _onNotificationTapped(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) {
      return;
    }
    AppServices.instance.handleNotificationPayload(payload);
  }
}

@pragma('vm:entry-point')
void _foregroundTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_AgentForegroundTaskHandler());
}

class _AgentForegroundTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {}

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/');
  }
}
