import 'package:agent_dance/agents/database/app_database.dart';
import 'package:agent_dance/app.dart';
import 'package:agent_dance/config/app_config.dart';
import 'package:agent_dance/services/app_services.dart';
import 'package:agent_dance/utils/logger.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final log = Logger('Main');
  log.info('Agent Dance 启动');
  await AppConfig.init();
  final db = AppDatabase();
  await AppServices.init(db);
  runApp(const AgentDanceApp());
}
