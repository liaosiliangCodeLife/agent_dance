import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

/// 服务器表
class Servers extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get host => text()();
  IntColumn get port => integer().withDefault(const Constant(8642))();
  TextColumn get agentType => text().withDefault(const Constant('hermes'))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  BoolColumn get isOnline => boolean().withDefault(const Constant(false))();
  IntColumn get latencyMs => integer().nullable()();
  TextColumn get iconKey => text().withDefault(const Constant('emoji:🤖'))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 会话表
class ChatSessions extends Table {
  TextColumn get id => text()();
  TextColumn get serverId => text().references(Servers, #id, onDelete: KeyAction.cascade)();
  TextColumn get title => text().withDefault(const Constant('新对话'))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get messageCount => integer().withDefault(const Constant(0))();
  TextColumn get lastMessagePreview => text().withDefault(const Constant(''))();
  IntColumn get unreadCount => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 消息表
class ChatMessages extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId => text().references(ChatSessions, #id, onDelete: KeyAction.cascade)();
  TextColumn get role => text()();
  TextColumn get content => text()();
  TextColumn get reasoningText => text().nullable()();
  TextColumn get imagesJson => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get tokenCount => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(tables: [Servers, ChatSessions, ChatMessages])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(servers, servers.iconKey);
          }
        },
      );

  // --- Server DAO ---
  Future<List<Server>> getAllServers() {
    return (select(servers)..orderBy([(t) => OrderingTerm.asc(t.name)])).get();
  }

  Future<Server?> getServerById(String id) {
    return (select(servers)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<void> upsertServer(ServersCompanion entry) {
    return into(servers).insertOnConflictUpdate(entry);
  }

  Future<void> deleteServer(String id) {
    return (delete(servers)..where((t) => t.id.equals(id))).go();
  }

  Future<void> updateServerStatus(String id, bool isOnline, int? latencyMs) {
    return (update(servers)..where((t) => t.id.equals(id))).write(
      ServersCompanion(
        isOnline: Value(isOnline),
        latencyMs: Value(latencyMs),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  // --- Session DAO ---
  Future<List<ChatSession>> getAllSessions() {
    return (select(chatSessions)
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
        .get();
  }

  Future<ChatSession?> getSessionById(String id) {
    return (select(chatSessions)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<void> upsertSession(ChatSessionsCompanion entry) {
    return into(chatSessions).insertOnConflictUpdate(entry);
  }

  Future<void> deleteSession(String id) {
    return (delete(chatSessions)..where((t) => t.id.equals(id))).go();
  }

  Future<void> clearUnread(String sessionId) {
    return (update(chatSessions)..where((t) => t.id.equals(sessionId))).write(
      const ChatSessionsCompanion(unreadCount: Value(0)),
    );
  }

  Future<void> deleteMessagesBySession(String sessionId) {
    return (delete(chatMessages)..where((t) => t.sessionId.equals(sessionId))).go();
  }

  // --- Message DAO ---
  Future<List<ChatMessage>> getMessagesBySession(String sessionId) {
    return (select(chatMessages)
          ..where((t) => t.sessionId.equals(sessionId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  Future<void> insertMessage(ChatMessagesCompanion entry) {
    return into(chatMessages).insert(entry);
  }

  Future<void> deleteAllData() async {
    await delete(chatMessages).go();
    await delete(chatSessions).go();
    await delete(servers).go();
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'agent_dance.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}

/// 数据库行转领域模型辅助
class DbMappers {
  static List<String>? decodeImages(String? json) {
    if (json == null || json.isEmpty) {
      return null;
    }
    final decoded = jsonDecode(json);
    if (decoded is List) {
      return decoded.map((e) => e.toString()).toList();
    }
    return null;
  }

  static String? encodeImages(List<String>? images) {
    if (images == null || images.isEmpty) {
      return null;
    }
    return jsonEncode(images);
  }
}
