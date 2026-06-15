import 'dart:convert';
import 'dart:io';

import 'package:agent_dance/agents/models/server.dart';
import 'package:agent_dance/agents/models/chat_state.dart';
import 'package:agent_dance/utils/logger.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// 图片选择与压缩
class ImageService {
  ImageService() : _picker = ImagePicker();

  final ImagePicker _picker;
  final _log = Logger('ImageService');

  Future<bool> requestCameraPermission() async {
    final status = await Permission.camera.request();
    return status.isGranted;
  }

  Future<bool> requestGalleryPermission() async {
    final photos = await Permission.photos.request();
    if (photos.isGranted) {
      return true;
    }
    final storage = await Permission.storage.request();
    return storage.isGranted;
  }

  Future<String?> pickAndCompress({required ImageSource source}) async {
    try {
      final file = await _picker.pickImage(source: source, imageQuality: 85);
      if (file == null) {
        return null;
      }
      return compressToBase64(File(file.path));
    } catch (e, st) {
      _log.error('图片选择失败', e, st);
      return null;
    }
  }

  /// 选择并保存用户头像到应用目录（F-401 / F-128）
  Future<String?> pickAndSaveAvatar({required ImageSource source}) async {
    try {
      final file = await _picker.pickImage(source: source, imageQuality: 90);
      if (file == null) {
        return null;
      }
      final dir = await getApplicationDocumentsDirectory();
      final targetPath = '${dir.path}/user_avatar.jpg';
      final result = await FlutterImageCompress.compressAndGetFile(
        file.path,
        targetPath,
        quality: 85,
        minWidth: 256,
        minHeight: 256,
      );
      return result?.path ?? targetPath;
    } catch (e, st) {
      _log.error('头像保存失败', e, st);
      return null;
    }
  }

  Future<String> compressToBase64(File file) async {
    final dir = await getTemporaryDirectory();
    final targetPath =
        '${dir.path}/compressed_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final result = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path,
      targetPath,
      quality: 85,
      minWidth: 2048,
      minHeight: 2048,
    );
    final bytes = await File(result?.path ?? file.path).readAsBytes();
    if (bytes.length > 2 * 1024 * 1024) {
      _log.warn('压缩后图片仍超过 2MB', {'size': bytes.length});
    }
    return base64Encode(bytes);
  }
}

/// 局域网智能体发现
class DiscoveryService {
  DiscoveryService();

  final _log = Logger('DiscoveryService');

  Future<List<DiscoveredAgent>> scanLocalAgents() async {
    final results = <DiscoveredAgent>[];
    final localIp = await _getLocalIp();
    if (localIp == null) {
      return results;
    }
    final parts = localIp.split('.');
    if (parts.length != 4) {
      return results;
    }
    final subnet = '${parts[0]}.${parts[1]}.${parts[2]}.';
    const ports = [8642, 8080];
    final futures = <Future<void>>[];

    for (var i = 1; i <= 254; i++) {
      final host = '$subnet$i';
      for (final port in ports) {
        futures.add(
          _probeHost(host, port).then((agent) {
            if (agent != null) {
              results.add(agent);
            }
          }),
        );
      }
    }

    await Future.wait(futures);
    _log.info('局域网扫描完成', {'count': results.length});
    return results;
  }

  Future<DiscoveredAgent?> _probeHost(String host, int port) async {
    try {
      final uri = Uri.parse('http://$host:$port/health');
      final response = await http.get(uri).timeout(const Duration(milliseconds: 800));
      if (response.statusCode == 200) {
        return DiscoveredAgent(
          name: 'Agent @ $host',
          host: host,
          port: port,
        );
      }
    } catch (_) {}
    return null;
  }

  Future<String?> _getLocalIp() async {
    try {
      for (final interface in await NetworkInterface.list()) {
        for (final addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      _log.warn('获取本机 IP 失败', {'error': e.toString()});
    }
    return null;
  }

  NetworkReachability detectReachability(String host) {
    if (host.contains('localhost') || host.startsWith('192.168.') || host.startsWith('10.')) {
      return NetworkReachability.lan;
    }
    if (host.contains('.') && !host.startsWith('http')) {
      return NetworkReachability.tunnel;
    }
    final uri = Uri.tryParse(host.startsWith('http') ? host : 'http://$host');
    if (uri != null &&
        (uri.host.startsWith('192.168.') || uri.host.startsWith('10.') || uri.host == 'localhost')) {
      return NetworkReachability.lan;
    }
    return NetworkReachability.tunnel;
  }
}
