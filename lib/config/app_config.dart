import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// 应用常量与配置读写
class AppConfig {
  AppConfig._();

  static const String defaultBaseUrl = 'http://localhost:8642';
  static const String defaultModel = 'agents-agent';
  static const String secureKeyPrefix = 'agents_';

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final deviceId = _prefs!.getString('device_id');
    if (deviceId == null || deviceId.isEmpty) {
      await _prefs!.setString('device_id', const Uuid().v4());
    }
  }

  static SharedPreferences get prefs {
    final p = _prefs;
    if (p == null) {
      throw StateError('AppConfig 尚未初始化');
    }
    return p;
  }

  static String get deviceId => prefs.getString('device_id') ?? const Uuid().v4();

  static String get nickname => prefs.getString('nickname') ?? 'Agent 用户';

  static Future<void> setNickname(String value) async {
    await prefs.setString('nickname', value);
  }

  static String? get userAvatarPath => prefs.getString('user_avatar_path');

  static Future<void> setUserAvatarPath(String path) async {
    await prefs.setString('user_avatar_path', path);
  }

  static Future<void> clearUserAvatarPath() async {
    await prefs.remove('user_avatar_path');
  }

  static ThemeMode get themeMode {
    final value = prefs.getString('theme_mode') ?? 'system';
    return switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  static Future<void> setThemeMode(ThemeMode mode) async {
    final value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await prefs.setString('theme_mode', value);
  }

  static String? get defaultServerId => prefs.getString('default_server_id');

  static Future<void> setDefaultServerId(String? serverId) async {
    if (serverId == null) {
      await prefs.remove('default_server_id');
    } else {
      await prefs.setString('default_server_id', serverId);
    }
  }

  static bool get biometricLockEnabled => prefs.getBool('biometric_lock') ?? false;

  static Future<void> setBiometricLockEnabled(bool enabled) async {
    await prefs.setBool('biometric_lock', enabled);
  }

  static Future<String?> readServerApiKey(String serverId) {
    return _secureStorage.read(key: '${secureKeyPrefix}server_key_$serverId');
  }

  static Future<void> writeServerApiKey(String serverId, String apiKey) {
    return _secureStorage.write(
      key: '${secureKeyPrefix}server_key_$serverId',
      value: apiKey,
    );
  }

  static Future<void> deleteServerApiKey(String serverId) {
    return _secureStorage.delete(key: '${secureKeyPrefix}server_key_$serverId');
  }

  static String buildBaseUrl(String host, int port) {
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
}
