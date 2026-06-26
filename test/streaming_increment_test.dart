import 'package:agent_dance/protocol/agents_api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('takeStreamingIncrement', () {
    test('空累计时返回全文作为增量', () {
      final result = takeStreamingIncrement('hello', '');
      expect(result.$1, 'hello');
      expect(result.$2, 'hello');
    });

    test('前缀匹配时只返回后缀', () {
      final result = takeStreamingIncrement('hello world', 'hello');
      expect(result.$1, 'hello world');
      expect(result.$2, ' world');
    });

    test('前缀相同无新内容时返回 null 增量', () {
      final result = takeStreamingIncrement('hello', 'hello');
      expect(result.$1, 'hello');
      expect(result.$2, isNull);
    });

    test('逐字增量 token 时追加', () {
      const accumulated = '老';
      const incoming = '板';
      final result = takeStreamingIncrement(incoming, accumulated);
      expect(result.$1, '老板');
      expect(result.$2, '板');
    });
  });
}
