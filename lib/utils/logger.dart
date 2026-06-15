import 'dart:developer' as developer;

/// 日志级别
enum LogLevel {
  debug,
  info,
  warn,
  error,
}

/// 日志输出目标
enum LogOutput {
  console,
  file,
}

/// 统一日志工具
class Logger {
  Logger(this.tag);

  final String tag;
  static LogLevel minLevel = LogLevel.debug;
  static LogOutput output = LogOutput.console;
  static final List<String> _fileBuffer = <String>[];

  void debug(String message, [Map<String, Object?>? context]) {
    _log(LogLevel.debug, message, context);
  }

  void info(String message, [Map<String, Object?>? context]) {
    _log(LogLevel.info, message, context);
  }

  void warn(String message, [Map<String, Object?>? context]) {
    _log(LogLevel.warn, message, context);
  }

  void error(
    String message,
    Object? error, [
    StackTrace? stackTrace,
    Map<String, Object?>? context,
  ]) {
    _log(LogLevel.error, message, context, error: error, stackTrace: stackTrace);
  }

  static void setOutput(LogOutput target) {
    output = target;
  }

  static List<String> getRecentLogs({LogLevel? filter}) {
    if (filter == null) {
      return List<String>.from(_fileBuffer);
    }
    final prefix = filter.name.toUpperCase();
    return _fileBuffer.where((line) => line.contains('[$prefix]')).toList();
  }

  static void clearLogs() {
    _fileBuffer.clear();
  }

  void _log(
    LogLevel level,
    String message,
    Map<String, Object?>? context, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (level.index < minLevel.index) {
      return;
    }
    final ctx = context == null || context.isEmpty ? '' : ' $context';
    final err = error == null ? '' : ' error=$error';
    final stack = stackTrace == null ? '' : '\n$stackTrace';
    final line = '[${level.name.toUpperCase()}][$tag] $message$ctx$err$stack';

    if (output == LogOutput.console || level.index >= LogLevel.info.index) {
      developer.log(line, name: tag, level: _developerLevel(level));
    }
    _fileBuffer.add(line);
    if (_fileBuffer.length > 2000) {
      _fileBuffer.removeRange(0, 500);
    }
  }

  int _developerLevel(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return 500;
      case LogLevel.info:
        return 800;
      case LogLevel.warn:
        return 900;
      case LogLevel.error:
        return 1000;
    }
  }
}
