import 'package:agent_dance/agents/database/app_database.dart';
import 'package:agent_dance/agents/models/chat_state.dart';
import 'package:agent_dance/agents/models/server.dart';
import 'package:agent_dance/agents/repositories/chat_repository.dart';
import 'package:agent_dance/config/app_config.dart';
import 'package:agent_dance/utils/logger.dart';
import 'package:agent_dance/utils/media_services.dart';
import 'package:flutter/foundation.dart';

/// 数据库单例 holder
class AppDatabaseHolder {
  AppDatabaseHolder(this.database);
  final AppDatabase database;
}

/// 服务器列表 ViewModel
class ServerListViewModel extends ChangeNotifier {
  ServerListViewModel({required ServerRepository serverRepository})
      : _serverRepository = serverRepository,
        _discoveryService = DiscoveryService();

  final ServerRepository _serverRepository;
  final DiscoveryService _discoveryService;
  final _log = Logger('ServerListViewModel');

  List<AgentServer> servers = [];
  bool isLoading = false;
  String? testResultMessage;
  int? testLatencyMs;
  NetworkReachability? reachability;

  Future<void> loadServers() async {
    isLoading = true;
    notifyListeners();
    try {
      servers = await _serverRepository.getAllServers();
      await _serverRepository.refreshAllServerStatus();
      servers = await _serverRepository.getAllServers();
    } catch (e, st) {
      _log.error('加载服务器失败', e, st);
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<AgentServer> saveServer({
    String? id,
    required String name,
    required String host,
    required int port,
    required AgentType agentType,
    required String apiKey,
    String iconKey = 'emoji:🤖',
  }) async {
    final server = await _serverRepository.saveServer(
      id: id,
      name: name,
      host: host,
      port: port,
      agentType: agentType,
      apiKey: apiKey,
      iconKey: iconKey,
    );
    await loadServers();
    return server;
  }

  Future<void> deleteServer(String id) async {
    await _serverRepository.deleteServer(id);
    await loadServers();
  }

  Future<void> testConnection({
    required String host,
    required int port,
    required String apiKey,
  }) async {
    reachability = _discoveryService.detectReachability(host);
    testLatencyMs = await _serverRepository.testConnection(
      host: host,
      port: port,
      apiKey: apiKey,
    );
    testResultMessage = testLatencyMs != null
        ? '连接成功，延迟 ${testLatencyMs}ms'
        : '连接失败，请检查地址和密钥';
    notifyListeners();
  }

  void clearTestResult() {
    testResultMessage = null;
    testLatencyMs = null;
    reachability = null;
    notifyListeners();
  }
}

/// 发现页 ViewModel
class DiscoverViewModel extends ChangeNotifier {
  DiscoverViewModel({required ServerRepository serverRepository})
      : _serverRepository = serverRepository,
        _discoveryService = DiscoveryService();

  final ServerRepository _serverRepository;
  final DiscoveryService _discoveryService;
  final _log = Logger('DiscoverViewModel');

  List<DiscoveredAgent> discoveredAgents = [];
  bool isScanning = false;

  Future<void> scanNearbyAgents() async {
    isScanning = true;
    notifyListeners();
    try {
      discoveredAgents = await _discoveryService.scanLocalAgents();
    } catch (e, st) {
      _log.error('扫描失败', e, st);
    } finally {
      isScanning = false;
      notifyListeners();
    }
  }

  Future<void> addDiscoveredAgent(DiscoveredAgent agent) async {
    await _serverRepository.saveServer(
      name: agent.name,
      host: agent.host,
      port: agent.port,
      agentType: AgentType.hermes,
      apiKey: '',
    );
  }
}

/// 个人页 ViewModel
class ProfileViewModel extends ChangeNotifier {
  ProfileViewModel({required AppDatabaseHolder dbHolder}) : _db = dbHolder;

  final AppDatabaseHolder _db;
  String nickname = '';
  String deviceId = '';
  String? avatarPath;
  bool biometricEnabled = false;

  Future<void> load() async {
    nickname = AppConfig.nickname;
    deviceId = AppConfig.deviceId;
    avatarPath = AppConfig.userAvatarPath;
    biometricEnabled = AppConfig.biometricLockEnabled;
    notifyListeners();
  }

  Future<void> updateAvatar(String path) async {
    await AppConfig.setUserAvatarPath(path);
    avatarPath = path;
    notifyListeners();
  }

  Future<void> updateNickname(String value) async {
    await AppConfig.setNickname(value);
    nickname = value;
    notifyListeners();
  }

  Future<void> setBiometricEnabled(bool value) async {
    await AppConfig.setBiometricLockEnabled(value);
    biometricEnabled = value;
    notifyListeners();
  }

  Future<void> clearCache() async {
    Logger.clearLogs();
  }

  Future<void> clearAllData() async {
    await _db.database.deleteAllData();
  }
}
